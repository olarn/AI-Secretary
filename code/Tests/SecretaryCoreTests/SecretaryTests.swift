import FunctionalCore
import XCTest
import AssistantState
import ProjectRegistry
import Permissions
import ToolAdapters
import LLMProvider
@testable import SecretaryCore

// MARK: - Test doubles

final class SpyAdapter: CodeToolAdapter {
    var toolID: String { GitReadOnlyAdapter.toolIdentifier }
    private(set) var runCalls: [(CodeToolOperation, Project)] = []
    var stubbedResult: ToolResult = ToolResult(output: "ok", exitCode: 0, commandSummary: "git status")
    var stubbedError: ToolError?

    func summary(for operation: CodeToolOperation) -> String { "git \(operation.rawValue)" }

    func run(_ operation: CodeToolOperation, in project: Project) -> Either<ToolError, ToolResult> {
        runCalls.append((operation, project))
        return Option.fromOptional(stubbedError).fold({ .right(self.stubbedResult) }, { .left($0) })
    }
}

/// Emits canned stream events (or an error) with no network or API key.
final class FakeChatProvider: ChatProvider, @unchecked Sendable {
    enum Script {
        case events([ChatStreamEvent])
        case failure(ChatError)
    }

    private let script: Script
    private(set) var callCount = 0
    private(set) var lastMessages: [ChatMessage] = []
    private(set) var lastModel: ChatModel?  // nil also means 'inherit'
    private(set) var lastEffort: Effort?
    private(set) var lastSystem: String?

    init(_ script: Script) { self.script = script }

    func stream(
        messages: [ChatMessage],
        model: Option<ChatModel>,
        effort: Option<Effort>,
        maxTokens: Int,
        system: Option<String>
    ) -> ChatStream {
        callCount += 1
        lastMessages = messages
        lastModel = model.toOptional()
        lastEffort = effort.toOptional()
        lastSystem = system.toOptional()
        return AsyncStream { continuation in
            switch script {
            case .events(let events):
                for event in events { continuation.yield(.right(event)) }
            case .failure(let error):
                continuation.yield(.left(error))
            }
            continuation.finish()
        }
    }
}

// MARK: - Intent classification

final class RuleBasedIntentClassifierTests: XCTestCase {
    private let classifier = RuleBasedIntentClassifier()

    func testRecognisesEachSupportedOperation() {
        let cases: [(String, CodeToolOperation)] = [
            ("git status", .status),
            ("show me the diff", .diffStat),
            ("what are the recent commits", .recentLog),
            ("which branch am I on", .currentBranch)
        ]

        for (text, expected) in cases {
            guard case .codeTool(let operation, _) = classifier.classify(text) else {
                return XCTFail("Expected codeTool for “\(text)”")
            }
            XCTAssertEqual(operation, expected, "for “\(text)”")
        }
    }

    func testExtractsProjectNameAfterIn() {
        guard case .codeTool(_, let query) = classifier.classify("git status in AI-Secretary") else {
            return XCTFail("Expected codeTool")
        }
        XCTAssertEqual(query, .some("ai-secretary"))
    }

    func testNoProjectPhraseYieldsAnAbsentQuery() {
        guard case .codeTool(_, let query) = classifier.classify("git status") else {
            return XCTFail("Expected codeTool")
        }
        XCTAssertEqual(query, Option.none())
    }

    func testUnrecognisedTextIsUnknownRatherThanAGuess() {
        for text in ["delete everything", "rm -rf /", "make me a sandwich", ""] {
            guard case .unknown = classifier.classify(text) else {
                return XCTFail("“\(text)” must classify as unknown")
            }
        }
    }

    func testHelpIsRecognised() {
        XCTAssertEqual(classifier.classify("help"), .help)
    }
}

// MARK: - Orchestration

@MainActor
final class SecretaryTests: XCTestCase {
    private var machine: AssistantStateMachine!
    private var adapter: SpyAdapter!

    private let project = Project(
        name: "Fixture",
        path: "/tmp/fixture",
        allowedTools: [GitReadOnlyAdapter.toolIdentifier]
    )

    override func setUp() {
        super.setUp()
        machine = AssistantStateMachine()
        adapter = SpyAdapter()
    }

    private func makeSecretary(
        projects: [Project],
        chat: FakeChatProvider = FakeChatProvider(.events([.completed(stopReason: .none(), usage: .none())]))
    ) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: projects)),
            adapter: adapter,
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: chat
        )
    }

    /// Chat replies stream on a background task; give them time to land.
    private func waitUntilIdle(timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while machine.state != .idle && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testFirstRequestAsksForApprovalAndRunsNothingYet() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")

        guard case .approval(let request, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected an approval prompt, got \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(request.project, project)
        XCTAssertTrue(adapter.runCalls.isEmpty, "Nothing may run before approval")
    }

    func testGrantingApprovalRunsTheToolAndReportsSuccess() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        XCTAssertEqual(adapter.runCalls.count, 1)
        XCTAssertEqual(adapter.runCalls.first?.0, .status)
        XCTAssertEqual(machine.state, .idle, "Task should complete back to idle")
        XCTAssertTrue(secretary.transcript.last?.text.contains("ok") ?? false)
    }

    func testDenyingApprovalRunsNothing() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: false)

        XCTAssertTrue(adapter.runCalls.isEmpty)
        XCTAssertEqual(secretary.pendingDecision, .none())
        XCTAssertEqual(machine.state, .idle)
    }

    func testSecondRequestSkipsApprovalForTheSameProjectAndTool() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        secretary.submit("git status")

        XCTAssertEqual(secretary.pendingDecision, .none(), "Approved project/tool should not re-prompt")
        XCTAssertEqual(adapter.runCalls.count, 2)
    }

    func testUnknownProjectNameNeverRunsAnything() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status in nonexistent-project")

        XCTAssertTrue(adapter.runCalls.isEmpty)
        XCTAssertEqual(secretary.pendingDecision, .none())
        XCTAssertTrue(secretary.transcript.last?.text.contains("No registered project") ?? false)
    }

    func testAmbiguousProjectAsksUserToChooseBeforeRunning() {
        let a = Project(name: "Alpha", path: "/tmp/a", allowedTools: [GitReadOnlyAdapter.toolIdentifier])
        let b = Project(name: "AlphaBeta", path: "/tmp/b", allowedTools: [GitReadOnlyAdapter.toolIdentifier])
        let secretary = makeSecretary(projects: [a, b])

        secretary.submit("git status in alph")

        guard case .projectChoice(let candidates, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected a project choice prompt")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(adapter.runCalls.isEmpty)
    }

    func testChoosingAProjectContinuesIntoApproval() {
        let a = Project(name: "Alpha", path: "/tmp/a", allowedTools: [GitReadOnlyAdapter.toolIdentifier])
        let b = Project(name: "AlphaBeta", path: "/tmp/b", allowedTools: [GitReadOnlyAdapter.toolIdentifier])
        let secretary = makeSecretary(projects: [a, b])

        secretary.submit("git status in alph")
        secretary.choose(project: b)

        guard case .approval(let request, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected approval after choosing a project")
        }
        XCTAssertEqual(request.project, b)
    }

    /// A tool the project never listed is asked about, not refused.
    ///
    /// This used to assert the opposite — no prompt, a red "denied by policy",
    /// nothing the person could do from the chat. The rule now is that nothing
    /// is blocked outright; what changes with the allowlist is how loudly the
    /// card speaks, not whether there is one. What must stay true either way is
    /// the second assertion: nothing ran on the way to asking.
    func testToolNotAllowlistedOnProjectAsksInsteadOfRefusing() {
        let locked = Project(name: "Locked", path: "/tmp/locked", allowedTools: [])
        let secretary = makeSecretary(projects: [locked])

        secretary.submit("git status")

        guard case .approval(let request, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected a card, not a refusal")
        }
        XCTAssertTrue(request.outsideAllowlist, "the card has to be able to say which list this steps past")
        XCTAssertTrue(adapter.runCalls.isEmpty, "still nothing runs before the answer")
        XCTAssertTrue(secretary.transcript.last?.text.contains("allowed-tools list") ?? false)
    }

    /// A folder no project contains is a question, not a wall.
    ///
    /// It used to end the turn: "it isn't inside <project>". Watching is reading,
    /// so it does need a yes — but there was no way to give one, which left a
    /// rule where a choice belonged.
    func testWatchingAFolderOutsideEveryProjectAsksInsteadOfRefusing() throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let registered = Project(name: "Registered", path: "/tmp/registered")
        let secretary = makeSecretary(projects: [registered])

        secretary.submit("/watch \(outside.path)")

        guard case .approval(let request, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected a card, not a refusal")
        }
        // The resolved path, because `/tmp` is a link to `/private/tmp` and a
        // card naming the one while reading the other is the failure worth
        // guarding.
        let resolved = outside.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertTrue(
            request.commandSummary.contains(resolved),
            "The card has to name where the reading happens. Got: \(request.commandSummary)"
        )
        XCTAssertTrue(secretary.activeWatches.isEmpty, "nothing is watched before the answer")
    }

    /// Saying yes covers the folder, and nothing else. It is not added to the
    /// registry, so it does not come back tomorrow as a project the assistant
    /// may work in.
    func testApprovingAnOutsideFolderDoesNotRegisterIt() throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let registered = Project(name: "Registered", path: "/tmp/registered")
        let store = InMemoryProjectStore(projects: [registered])
        let registry = ProjectRegistry(store: store)
        let secretary = Secretary(
            stateMachine: machine,
            registry: registry,
            adapter: adapter,
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: FakeChatProvider(.events([.completed(stopReason: .none(), usage: .none())]))
        )

        secretary.submit("/watch \(outside.path)")
        secretary.resolvePendingApproval(granted: true)

        XCTAssertEqual(secretary.activeWatches.count, 1, "the yes started the watch")
        XCTAssertEqual(registry.projects.map(\.name), ["Registered"], "and added nothing to the registry")
        XCTAssertEqual(
            store.load().toOption().toOptional()?.map(\.name),
            ["Registered"],
            "nor to what gets written back to disk"
        )
        XCTAssertFalse(
            registry.projects.contains { $0.path == outside.path },
            "the approved folder is carried in memory, not registered"
        )
    }

    /// The tick is where an approved outside folder could quietly stop working.
    ///
    /// The loop re-resolves through the adapter every time rather than reusing
    /// a URL from the start, so the escape check keeps running. That is the
    /// point — and it also means a throwaway project that resolves once at
    /// approval but not afterwards would leave a watch that reports nothing and
    /// says nothing, because a failed resolve is a `continue`. Silence is the
    /// failure mode, which is why this asserts a report rather than an absence
    /// of errors.
    func testAnApprovedOutsideFolderKeepsResolvingOnEveryLook() throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let secretary = makeSecretary(projects: [Project(name: "Registered", path: "/tmp/registered")])
        secretary.submit("/watch \(outside.path)")
        secretary.resolvePendingApproval(granted: true)
        XCTAssertEqual(secretary.activeWatches.count, 1)

        try "hello".write(
            to: outside.appendingPathComponent("new.txt"),
            atomically: true,
            encoding: .utf8
        )
        secretary.tickWatch()

        XCTAssertTrue(
            secretary.transcript.last?.text.contains("new.txt") ?? false,
            "The look after approval has to see the folder. Got: \(secretary.transcript.last?.text ?? "nothing")"
        )
    }

    /// A symlink inside the approved folder still can't lead out of it. The
    /// boundary moved to the folder that was agreed to; it did not disappear.
    func testTheEscapeCheckNowGuardsTheApprovedFolder() throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let folder = watchOnlyProject(at: outside)
        let adapter = FileReadOnlyAdapter()
        XCTAssertTrue(
            adapter.resolve("", in: folder).toOption().toOptional() != nil,
            "the folder itself resolves, or the watch would go silent"
        )
        XCTAssertNil(
            adapter.resolve("../elsewhere", in: folder).toOption().toOptional(),
            "and climbing out of it does not"
        )
    }

    func testNonGitMessageIsRoutedToChatAndStreamsAReply() async {
        let chat = FakeChatProvider(.events([
            .thinking,
            .textDelta("Hi"),
            .textDelta(" there!"),
            .completed(stopReason: .some("end_turn"), usage: .some(ChatUsage(inputTokens: 5, outputTokens: 2)))
        ]))
        let secretary = makeSecretary(projects: [project], chat: chat)

        secretary.submit("hello, how are you?")
        await waitUntilIdle()

        XCTAssertEqual(chat.callCount, 1)
        XCTAssertTrue(adapter.runCalls.isEmpty, "Chat must not touch the git adapter")
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(secretary.transcript.last?.text, "Hi there!")
        XCTAssertEqual(chat.lastMessages.last?.content, "hello, how are you?")
    }

    func testChatWalksThinkingThenWorkingThenSuccess() async {
        let chat = FakeChatProvider(.events([
            .thinking,
            .textDelta("ok"),
            .completed(stopReason: .none(), usage: .none())
        ]))
        let secretary = makeSecretary(projects: [project], chat: chat)

        secretary.submit("what's the weather like on the moon?")
        await waitUntilIdle()

        XCTAssertEqual(
            machine.history.map(\.to),
            [.listening, .thinking, .working, .success, .idle]
        )
    }

    func testChatRefusalEndsInError() async {
        let chat = FakeChatProvider(.events([
            .completed(stopReason: .some("refusal"), usage: .none())
        ]))
        let secretary = makeSecretary(projects: [project], chat: chat)

        secretary.submit("do something disallowed")
        await waitUntilIdle()

        XCTAssertTrue(machine.history.contains { $0.to == .error })
        XCTAssertEqual(machine.state, .idle)
    }

    func testChatNetworkErrorIsReportedNotCrashed() async {
        let chat = FakeChatProvider(.failure(ChatError.network("the network went away")))
        let secretary = makeSecretary(projects: [project], chat: chat)

        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertTrue(machine.history.contains { $0.to == .error })
        XCTAssertTrue(secretary.transcript.last?.text.contains("Network error") ?? false)
    }

    func testSlashModelSwitchesModelWithoutHittingTheNetwork() {
        let chat = FakeChatProvider(.events([]))
        let secretary = makeSecretary(projects: [project], chat: chat)

        secretary.submit("/model claude-opus-4-8")

        XCTAssertEqual(secretary.model, .some(.opus48))
        XCTAssertEqual(chat.callCount, 0)
        // Confirmed by display name now — the settings panel and the slash
        // command share one entry point, and a name reads better than an id.
        XCTAssertTrue(secretary.transcript.last?.text.contains("Claude Opus 4.8") ?? false,
                      "Got: \(secretary.transcript.last?.text ?? "-")")
    }

    func testSlashEffortRejectsUnknownLevel() {
        let secretary = makeSecretary(projects: [project])
        let original = secretary.effort

        secretary.submit("/effort turbo")

        XCTAssertEqual(secretary.effort, original)
        XCTAssertTrue(secretary.transcript.last?.text.contains("Unknown effort") ?? false)
    }

    func testGitKeywordStillRoutesToTheGitPipeline() {
        let chat = FakeChatProvider(.events([]))
        let secretary = makeSecretary(projects: [project], chat: chat)

        secretary.submit("git status")

        guard case .approval = secretary.pendingDecision.toOptional() else {
            return XCTFail("git command should still reach the approval prompt")
        }
        XCTAssertEqual(chat.callCount, 0, "A git command must not go to chat")
    }

    func testAdapterFailureIsReportedWithoutCrashing() {
        let secretary = makeSecretary(projects: [project])
        adapter.stubbedError = ToolError.notAGitRepository("/tmp/fixture")

        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(secretary.transcript.last?.text.contains("Not a Git repository") ?? false)
    }

    func testNonZeroExitIsReportedAsFailure() {
        let secretary = makeSecretary(projects: [project])
        adapter.stubbedResult = ToolResult(output: "fatal", exitCode: 128, commandSummary: "git status")

        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        XCTAssertTrue(secretary.transcript.last?.text.contains("128") ?? false)
        XCTAssertEqual(machine.state, .idle)
    }

    func testAuditTrailCoversTheWholeApprovedRun() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        let kinds = secretary.auditEntries.map(\.kind)
        XCTAssertEqual(
            kinds,
            [.requestReceived, .intentClassified, .projectResolved,
             .approvalRequested, .approvalGranted, .executionStarted, .executionFinished]
        )

        let taskIDs = Set(secretary.auditEntries.map(\.taskID))
        XCTAssertEqual(taskIDs.count, 1, "All entries for one request share a correlation ID")
    }

    func testStateMachineWalksTheFullLifecycleForAnApprovedRun() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        XCTAssertEqual(
            machine.history.map(\.to),
            [.listening, .thinking, .working, .success, .idle]
        )
    }
}
