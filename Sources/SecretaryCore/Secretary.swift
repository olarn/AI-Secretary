import Foundation
import Observation
import AssistantState
import ProjectRegistry
import Permissions
import ToolAdapters
import LLMProvider

/// A message shown in the conversation transcript. `text` is mutable so a
/// streamed reply can grow token-by-token in the same entry.
public struct TranscriptEntry: Identifiable, Equatable, Sendable {
    public enum Speaker: Sendable { case user, secretary }

    public let id = UUID()
    public let speaker: Speaker
    public var text: String
    public let timestamp: Date

    public init(speaker: Speaker, text: String, timestamp: Date = Date()) {
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}

/// A tool operation the Secretary can run through the approval pipeline: either
/// a read-only Git command or a read-only file access. Both are `.readOnly`, so
/// they share the same approval and audit path.
public enum PlannedOperation: Equatable, Sendable {
    case git(CodeToolOperation)
    case file(FileOperation)

    public var actionClass: ActionClass {
        switch self {
        case .git(let op): return op.actionClass
        case .file(let op): return op.actionClass
        }
    }

    public var humanDescription: String {
        switch self {
        case .git(let op): return op.humanDescription
        case .file(let op): return op.humanDescription
        }
    }
}

/// A request waiting on the user: either confirm an action, or pick a project.
public enum PendingDecision: Equatable, Sendable {
    case approval(ApprovalRequest, operation: PlannedOperation)
    case projectChoice(candidates: [Project], operation: PlannedOperation)
}

/// Orchestration layer. Interprets a message, resolves context, applies policy,
/// and invokes a tool — or, for conversational messages, streams a reply from
/// the Claude API. Drives the shared `AssistantState` machine so the character
/// UI reflects real work.
///
/// `@MainActor` because every mutation here feeds an `@Observable` SwiftUI view;
/// the chat provider does its network work off the main actor and this type
/// consumes the stream back on the main actor.
@MainActor
@Observable
public final class Secretary {
    public private(set) var transcript: [TranscriptEntry] = []
    public private(set) var pendingDecision: PendingDecision?
    public private(set) var model: ChatModel = .sonnet5
    public private(set) var effort: Effort = .medium

    @ObservationIgnored public let stateMachine: AssistantStateMachine
    @ObservationIgnored private let registry: ProjectRegistry
    @ObservationIgnored private let policy: PermissionPolicy
    @ObservationIgnored private let adapter: CodeToolAdapter
    @ObservationIgnored private let fileAdapter: FileToolAdapter
    @ObservationIgnored private let classifier: IntentClassifying
    @ObservationIgnored private let audit: AuditLogging
    @ObservationIgnored private let chatProvider: ChatProvider

    @ObservationIgnored private var activeTaskID: String?
    @ObservationIgnored private var conversation: [ChatMessage] = []
    @ObservationIgnored private var streamingTask: Task<Void, Never>?

    private let chatMaxTokens = 4096

    public init(
        stateMachine: AssistantStateMachine,
        registry: ProjectRegistry,
        policy: PermissionPolicy = DefaultPermissionPolicy(),
        adapter: CodeToolAdapter = GitReadOnlyAdapter(),
        fileAdapter: FileToolAdapter = FileReadOnlyAdapter(),
        classifier: IntentClassifying = RuleBasedIntentClassifier(),
        audit: AuditLogging = AuditLog(),
        chatProvider: ChatProvider
    ) {
        self.stateMachine = stateMachine
        self.registry = registry
        self.policy = policy
        self.adapter = adapter
        self.fileAdapter = fileAdapter
        self.classifier = classifier
        self.audit = audit
        self.chatProvider = chatProvider
    }

    public var auditEntries: [AuditEntry] { audit.entries }

    // MARK: - Entry point

    public func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingDecision = nil
        say(.user, trimmed)

        // Local commands first: never hit the network or the state machine.
        if trimmed.hasPrefix("/") {
            handleSlashCommand(trimmed)
            return
        }
        if trimmed.lowercased() == "help" || trimmed == "?" {
            say(.secretary, helpText)
            return
        }

        let taskID = String(UUID().uuidString.prefix(8).lowercased())
        activeTaskID = taskID
        audit.record(AuditEntry(taskID: taskID, kind: .requestReceived, detail: "message received"))

        stateMachine.send(.userBeganInput, reason: "user submitted a message", taskID: taskID)
        stateMachine.send(.beginInterpreting, reason: "classifying intent", taskID: taskID)

        let intent = classifier.classify(trimmed)
        audit.record(AuditEntry(taskID: taskID, kind: .intentClassified, detail: describe(intent)))

        switch intent {
        case .help:
            finish(success: true, message: helpText, reason: "answered help")
        case .codeTool(let operation, let projectQuery):
            handleTool(operation: .git(operation), projectQuery: projectQuery)
        case .fileTool(let operation, let projectQuery):
            handleTool(operation: .file(operation), projectQuery: projectQuery)
        case .unknown:
            startChat(trimmed, taskID: taskID)
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

    // MARK: - Slash commands

    private func handleSlashCommand(_ text: String) {
        let parts = text.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts.first?.lowercased() ?? ""
        let argument = parts.count > 1 ? parts[1] : nil

        switch command {
        case "model":
            guard let argument else {
                let list = ChatModel.known.map(\.id).joined(separator: ", ")
                say(.secretary, "Model: \(model.id)\nAvailable: \(list)")
                return
            }
            if let resolved = ChatModel.named(argument) {
                model = resolved
                say(.secretary, "Model set to \(resolved.id).")
            } else {
                say(.secretary, "Unknown model “\(argument)”. Available: \(ChatModel.known.map(\.id).joined(separator: ", "))")
            }

        case "effort":
            guard let argument else {
                let list = Effort.allCases.map(\.rawValue).joined(separator: ", ")
                say(.secretary, "Effort: \(effort.rawValue)\nAvailable: \(list)")
                return
            }
            if let resolved = Effort.named(argument) {
                effort = resolved
                say(.secretary, "Effort set to \(resolved.rawValue).")
            } else {
                say(.secretary, "Unknown effort “\(argument)”. Available: \(Effort.allCases.map(\.rawValue).joined(separator: ", "))")
            }

        default:
            say(.secretary, "Unknown command “/\(command)”. Try /model or /effort.")
        }
    }

    // MARK: - Chat

    private func startChat(_ text: String, taskID: String) {
        conversation.append(ChatMessage(role: .user, content: text))

        let replyEntry = TranscriptEntry(speaker: .secretary, text: "")
        transcript.append(replyEntry)
        let replyID = replyEntry.id

        audit.record(AuditEntry(taskID: taskID, kind: .executionStarted, detail: "chat model=\(model.id) effort=\(effort.rawValue)"))

        let stream = chatProvider.stream(
            messages: conversation,
            model: model,
            effort: effort,
            maxTokens: chatMaxTokens,
            system: Self.systemPrompt
        )

        streamingTask?.cancel()
        streamingTask = Task { [weak self] in
            var reply = ""
            var movedToWorking = false

            func ensureWorking() {
                guard let self, !movedToWorking else { return }
                self.stateMachine.send(.beginExecuting, reason: "streaming reply", taskID: taskID, toolStatus: "streaming")
                movedToWorking = true
            }

            do {
                for try await event in stream {
                    guard let self else { return }
                    switch event {
                    case .thinking:
                        break // stay in THINKING until the first token
                    case .textDelta(let chunk):
                        ensureWorking()
                        reply += chunk
                        self.updateEntry(id: replyID, text: reply)
                    case .completed(let stopReason, let usage):
                        ensureWorking()
                        self.audit.record(AuditEntry(
                            taskID: taskID,
                            kind: .executionFinished,
                            detail: "stop=\(stopReason ?? "end_turn") in=\(usage?.inputTokens ?? 0) out=\(usage?.outputTokens ?? 0)"
                        ))
                        if stopReason == "refusal" {
                            self.finishChat(entryID: replyID, taskID: taskID, success: false,
                                            finalText: reply.isEmpty ? "(The model declined to respond.)" : reply)
                        } else {
                            self.conversation.append(ChatMessage(role: .assistant, content: reply))
                            self.finishChat(entryID: replyID, taskID: taskID, success: true, finalText: reply)
                        }
                    }
                }
            } catch {
                guard let self else { return }
                ensureWorking()
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.audit.record(AuditEntry(taskID: taskID, kind: .failed, detail: "chat error"))
                self.finishChat(entryID: replyID, taskID: taskID, success: false, finalText: message)
            }
            self?.streamingTask = nil
        }
    }

    private func finishChat(entryID: UUID, taskID: String, success: Bool, finalText: String) {
        updateEntry(id: entryID, text: finalText)
        if stateMachine.state != .working {
            stateMachine.send(.beginExecuting, reason: "chat completed", taskID: taskID)
        }
        stateMachine.send(success ? .succeeded : .failed, reason: success ? "chat reply delivered" : "chat failed", taskID: taskID)
        stateMachine.send(.acknowledge, reason: "result delivered", taskID: taskID)
        activeTaskID = nil
    }

    private func updateEntry(id: UUID, text: String) {
        guard let index = transcript.firstIndex(where: { $0.id == id }) else { return }
        transcript[index].text = text
    }

    // MARK: - Git pipeline

    private func handleTool(operation: PlannedOperation, projectQuery: String?) {
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

    private func proceed(operation: PlannedOperation, project: Project) {
        let taskID = activeTaskID ?? "-"

        let request = ApprovalRequest(
            taskID: taskID,
            toolID: toolID(for: operation),
            actionClass: operation.actionClass,
            project: project,
            commandSummary: summary(for: operation),
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

    private func execute(_ operation: PlannedOperation, in project: Project) {
        let taskID = activeTaskID ?? "-"
        let summary = summary(for: operation)

        stateMachine.send(.beginExecuting, reason: summary, taskID: taskID, toolStatus: "running")
        audit.record(AuditEntry(taskID: taskID, kind: .executionStarted, detail: summary))

        do {
            let result = try run(operation, in: project)
            audit.record(AuditEntry(taskID: taskID, kind: .executionFinished, detail: "exit \(result.exitCode)"))

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

    // MARK: - Adapter dispatch

    private func toolID(for operation: PlannedOperation) -> String {
        switch operation {
        case .git: return adapter.toolID
        case .file: return fileAdapter.toolID
        }
    }

    private func summary(for operation: PlannedOperation) -> String {
        switch operation {
        case .git(let op): return adapter.summary(for: op)
        case .file(let op): return fileAdapter.summary(for: op)
        }
    }

    private func run(_ operation: PlannedOperation, in project: Project) throws -> ToolResult {
        switch operation {
        case .git(let op): return try adapter.run(op, in: project)
        case .file(let op): return try fileAdapter.run(op, in: project)
        }
    }

    // MARK: - Helpers

    private func finish(success: Bool, message: String, reason: String, toolStatus: String? = nil) {
        let taskID = activeTaskID ?? "-"

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
        case .fileTool(let operation, let query):
            let kind = { switch operation { case .listDirectory: return "list"; case .readFile: return "read" } }()
            return "fileTool(\(kind) \(operation.relativePath)) project=\(query ?? "-")"
        case .help: return "help"
        case .unknown: return "chat"
        }
    }

    private static let systemPrompt = """
    You are the AI Secretary, a friendly macOS desktop companion. Chat naturally \
    and concisely. You can also run a small set of read-only Git commands (e.g. \
    "status in <project>") and read-only file access (e.g. "list src in <project>" \
    or "read README.md in <project>") — mention that only if relevant. Do not claim \
    to have taken actions you did not take.
    """

    private var helpText: String {
        """
        I can chat with you, and run these read-only Git commands in a registered project:
        • status — working tree status
        • diff — summary of uncommitted changes
        • branch — current branch
        • log — 20 most recent commits

        I can also read files in a registered project (read-only):
        • list [path] — list a directory, e.g. “list src in AI-Secretary”
        • read <path> — show a text file, e.g. “read README.md in AI-Secretary”

        Add “in <project>” to pick a project, e.g. “status in AI-Secretary”.
        Anything else I treat as a conversation.

        Slash commands:
        • /model <id> — switch the chat model
        • /effort <low|medium|high|xhigh|max> — adjust reasoning depth
        """
    }
}
