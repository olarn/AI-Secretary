import Foundation
import Observation
import AssistantState
import ProjectRegistry
import Permissions
import ToolAdapters

/// A message shown in the conversation transcript.
public struct TranscriptEntry: Identifiable, Equatable, Sendable {
    public enum Speaker: Sendable { case user, secretary }

    public let id = UUID()
    public let speaker: Speaker
    public let text: String
    public let timestamp: Date

    public init(speaker: Speaker, text: String, timestamp: Date = Date()) {
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}

/// A request waiting on the user: either confirm an action, or pick a project.
public enum PendingDecision: Equatable, Sendable {
    case approval(ApprovalRequest, operation: CodeToolOperation)
    case projectChoice(candidates: [Project], operation: CodeToolOperation)
}

/// Orchestration layer. Interprets a message, resolves context, applies policy,
/// and — only after that — invokes a tool. Drives the shared `AssistantState`
/// machine so the character UI reflects real work rather than mock transitions.
@Observable
public final class Secretary {
    public private(set) var transcript: [TranscriptEntry] = []
    public private(set) var pendingDecision: PendingDecision?

    @ObservationIgnored public let stateMachine: AssistantStateMachine
    @ObservationIgnored private let registry: ProjectRegistry
    @ObservationIgnored private let policy: PermissionPolicy
    @ObservationIgnored private let adapter: CodeToolAdapter
    @ObservationIgnored private let classifier: IntentClassifying
    @ObservationIgnored private let audit: AuditLogging

    @ObservationIgnored private var activeTaskID: String?

    public init(
        stateMachine: AssistantStateMachine,
        registry: ProjectRegistry,
        policy: PermissionPolicy = DefaultPermissionPolicy(),
        adapter: CodeToolAdapter = GitReadOnlyAdapter(),
        classifier: IntentClassifying = RuleBasedIntentClassifier(),
        audit: AuditLogging = AuditLog()
    ) {
        self.stateMachine = stateMachine
        self.registry = registry
        self.policy = policy
        self.adapter = adapter
        self.classifier = classifier
        self.audit = audit
    }

    public var auditEntries: [AuditEntry] { audit.entries }

    // MARK: - Entry point

    public func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let taskID = UUID().uuidString.prefix(8).lowercased()
        activeTaskID = String(taskID)
        pendingDecision = nil
        say(.user, trimmed)
        audit.record(AuditEntry(taskID: String(taskID), kind: .requestReceived, detail: "message received"))

        stateMachine.send(.userBeganInput, reason: "user submitted a message", taskID: String(taskID))
        stateMachine.send(.beginInterpreting, reason: "classifying intent", taskID: String(taskID))

        let intent = classifier.classify(trimmed)
        audit.record(AuditEntry(taskID: String(taskID), kind: .intentClassified, detail: describe(intent)))

        switch intent {
        case .help:
            finish(success: true, message: helpText, reason: "answered help")

        case .unknown:
            finish(
                success: false,
                message: "I didn't understand that. I currently handle: status, diff, branch, log. Type 'help' for details.",
                reason: "intent not recognised"
            )

        case .codeTool(let operation, let projectQuery):
            handleCodeTool(operation: operation, projectQuery: projectQuery)
        }
    }

    // MARK: - Decisions

    public func resolvePendingApproval(granted: Bool) {
        guard case .approval(let request, let operation) = pendingDecision else { return }
        pendingDecision = nil

        guard granted else {
            audit.record(AuditEntry(taskID: request.taskID, kind: .approvalDenied, detail: request.commandSummary))
            finish(success: false, message: "Cancelled — nothing was run.", reason: "user denied approval")
            return
        }

        audit.record(AuditEntry(taskID: request.taskID, kind: .approvalGranted, detail: request.commandSummary))
        policy.recordApproval(projectID: request.project.id, toolID: request.toolID)
        execute(operation, in: request.project)
    }

    public func choose(project: Project) {
        guard case .projectChoice(_, let operation) = pendingDecision else { return }
        pendingDecision = nil
        proceed(operation: operation, project: project)
    }

    public func cancelPendingDecision() {
        guard pendingDecision != nil else { return }
        pendingDecision = nil
        finish(success: false, message: "Cancelled.", reason: "user cancelled")
    }

    // MARK: - Pipeline

    private func handleCodeTool(operation: CodeToolOperation, projectQuery: String?) {
        let taskID = activeTaskID ?? "-"

        switch registry.resolve(query: projectQuery) {
        case .resolved(let project):
            audit.record(AuditEntry(taskID: taskID, kind: .projectResolved, detail: project.name))
            proceed(operation: operation, project: project)

        case .notFound(let query):
            finish(
                success: false,
                message: "No registered project matches “\(query)”. Add it in the project list first — I won't guess a folder path.",
                reason: "project not found"
            )

        case .ambiguous(let query, let candidates):
            say(.secretary, "Several projects match “\(query)”. Which one?")
            pendingDecision = .projectChoice(candidates: candidates, operation: operation)

        case .needsSelection(let candidates):
            if candidates.isEmpty {
                finish(
                    success: false,
                    message: "No projects are registered yet. Add one and I'll be able to work in it.",
                    reason: "registry empty"
                )
            } else {
                say(.secretary, "Which project should I look at?")
                pendingDecision = .projectChoice(candidates: candidates, operation: operation)
            }
        }
    }

    private func proceed(operation: CodeToolOperation, project: Project) {
        let taskID = activeTaskID ?? "-"

        let request = ApprovalRequest(
            taskID: taskID,
            toolID: adapter.toolID,
            actionClass: operation.actionClass,
            project: project,
            commandSummary: adapter.summary(for: operation),
            rationale: operation.humanDescription
        )

        switch policy.evaluate(request) {
        case .allowed:
            execute(operation, in: project)

        case .needsApproval(let request):
            audit.record(AuditEntry(taskID: taskID, kind: .approvalRequested, detail: request.commandSummary))
            say(.secretary, "May I run `\(request.commandSummary)` in \(project.name)?")
            pendingDecision = .approval(request, operation: operation)

        case .denied(let reason):
            finish(success: false, message: reason, reason: "denied by policy")
        }
    }

    private func execute(_ operation: CodeToolOperation, in project: Project) {
        let taskID = activeTaskID ?? "-"
        let summary = adapter.summary(for: operation)

        stateMachine.send(.beginExecuting, reason: summary, taskID: taskID, toolStatus: "running")
        audit.record(AuditEntry(taskID: taskID, kind: .executionStarted, detail: summary))

        do {
            let result = try adapter.run(operation, in: project)
            audit.record(
                AuditEntry(taskID: taskID, kind: .executionFinished, detail: "exit \(result.exitCode)")
            )

            let body = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.succeeded {
                finish(
                    success: true,
                    message: body.isEmpty ? "`\(summary)` finished with no output." : "`\(summary)`\n\n\(body)",
                    reason: "tool succeeded",
                    toolStatus: "exit 0"
                )
            } else {
                finish(
                    success: false,
                    message: "`\(summary)` exited with code \(result.exitCode).\n\n\(body)",
                    reason: "tool reported failure",
                    toolStatus: "exit \(result.exitCode)"
                )
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            audit.record(AuditEntry(taskID: taskID, kind: .failed, detail: message))
            finish(success: false, message: message, reason: "tool threw", toolStatus: "error")
        }
    }

    // MARK: - Helpers

    private func finish(success: Bool, message: String, reason: String, toolStatus: String? = nil) {
        let taskID = activeTaskID ?? "-"

        // The machine only accepts success/failure from WORKING, so a request
        // rejected before execution passes through it to keep transitions legal.
        if stateMachine.state != .working {
            stateMachine.send(.beginExecuting, reason: reason, taskID: taskID, toolStatus: toolStatus)
        }

        stateMachine.send(success ? .succeeded : .failed, reason: reason, taskID: taskID, toolStatus: toolStatus)
        say(.secretary, message)
        stateMachine.send(.acknowledge, reason: "result delivered", taskID: taskID)
        activeTaskID = nil
    }

    private func say(_ speaker: TranscriptEntry.Speaker, _ text: String) {
        transcript.append(TranscriptEntry(speaker: speaker, text: text))
    }

    private func describe(_ intent: Intent) -> String {
        switch intent {
        case .codeTool(let operation, let query):
            return "codeTool(\(operation.rawValue)) project=\(query ?? "-")"
        case .help: return "help"
        case .unknown: return "unknown"
        }
    }

    private var helpText: String {
        """
        I can run these read-only Git commands in a registered project:
        • status — working tree status
        • diff — summary of uncommitted changes
        • branch — current branch
        • log — 20 most recent commits

        Add “in <project>” to pick a project, e.g. “status in AI-Secretary”.
        I always ask before running anything in a project for the first time.
        """
    }
}
