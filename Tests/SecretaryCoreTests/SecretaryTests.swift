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
    var stubbedError: Error?

    func summary(for operation: CodeToolOperation) -> String { "git \(operation.rawValue)" }

    func run(_ operation: CodeToolOperation, in project: Project) throws -> ToolResult {
        runCalls.append((operation, project))
        if let stubbedError { throw stubbedError }
        return stubbedResult
    }
}

/// Emits canned stream events (or an error) with no network or API key.
final class FakeChatProvider: ChatProvider, @unchecked Sendable {
    enum Script {
        case events([ChatStreamEvent])
        case failure(Error)
    }

    private let script: Script
    private(set) var callCount = 0
    private(set) var lastMessages: [ChatMessage] = []
    private(set) var lastModel: ChatModel?
    private(set) var lastEffort: Effort?

    init(_ script: Script) { self.script = script }

    func stream(
        messages: [ChatMessage],
        model: ChatModel,
        effort: Effort,
        maxTokens: Int,
        system: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        callCount += 1
        lastMessages = messages
        lastModel = model
        lastEffort = effort
        return AsyncThrowingStream { continuation in
            switch script {
            case .events(let events):
                for event in events { continuation.yield(event) }
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            }
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
        XCTAssertEqual(query, "ai-secretary")
    }

    func testNoProjectPhraseYieldsNilQuery() {
        guard case .codeTool(_, let query) = classifier.classify("git status") else {
            return XCTFail("Expected codeTool")
        }
        XCTAssertNil(query)
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
    private var policy: DefaultPermissionPolicy!

    private let project = Project(
        name: "Fixture",
        path: "/tmp/fixture",
        allowedTools: [GitReadOnlyAdapter.toolIdentifier]
    )

    override func setUp() {
        super.setUp()
        machine = AssistantStateMachine()
        adapter = SpyAdapter()
        policy = DefaultPermissionPolicy()
    }

    private func makeSecretary(
        projects: [Project],
        chat: FakeChatProvider = FakeChatProvider(.events([.completed(stopReason: nil, usage: nil)]))
    ) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: projects)),
            policy: policy,
            adapter: adapter,
            classifier: RuleBasedIntentClassifier(),
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

        guard case .approval(let request, _) = secretary.pendingDecision else {
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
        XCTAssertNil(secretary.pendingDecision)
        XCTAssertEqual(machine.state, .idle)
    }

    func testSecondRequestSkipsApprovalForTheSameProjectAndTool() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        secretary.submit("git status")

        XCTAssertNil(secretary.pendingDecision, "Approved project/tool should not re-prompt")
        XCTAssertEqual(adapter.runCalls.count, 2)
    }

    func testUnknownProjectNameNeverRunsAnything() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status in nonexistent-project")

        XCTAssertTrue(adapter.runCalls.isEmpty)
        XCTAssertNil(secretary.pendingDecision)
        XCTAssertTrue(secretary.transcript.last?.text.contains("No registered project") ?? false)
    }

    func testAmbiguousProjectAsksUserToChooseBeforeRunning() {
        let a = Project(name: "Alpha", path: "/tmp/a", allowedTools: [GitReadOnlyAdapter.toolIdentifier])
        let b = Project(name: "AlphaBeta", path: "/tmp/b", allowedTools: [GitReadOnlyAdapter.toolIdentifier])
        let secretary = makeSecretary(projects: [a, b])

        secretary.submit("git status in alph")

        guard case .projectChoice(let candidates, _) = secretary.pendingDecision else {
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

        guard case .approval(let request, _) = secretary.pendingDecision else {
            return XCTFail("Expected approval after choosing a project")
        }
        XCTAssertEqual(request.project, b)
    }

    func testToolNotAllowlistedOnProjectIsDeniedWithoutPrompting() {
        let locked = Project(name: "Locked", path: "/tmp/locked", allowedTools: [])
        let secretary = makeSecretary(projects: [locked])

        secretary.submit("git status")

        XCTAssertNil(secretary.pendingDecision, "A denial must not offer an approval prompt")
        XCTAssertTrue(adapter.runCalls.isEmpty)
        XCTAssertTrue(secretary.transcript.last?.text.contains("not in the allowlist") ?? false)
    }

    func testNonGitMessageIsRoutedToChatAndStreamsAReply() async {
        let chat = FakeChatProvider(.events([
            .thinking,
            .textDelta("Hi"),
            .textDelta(" there!"),
            .completed(stopReason: "end_turn", usage: ChatUsage(inputTokens: 5, outputTokens: 2))
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
            .completed(stopReason: nil, usage: nil)
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
            .completed(stopReason: "refusal", usage: nil)
        ]))
        let secretary = makeSecretary(projects: [project], chat: chat)

        secretary.submit("do something disallowed")
        await waitUntilIdle()

        XCTAssertTrue(machine.history.contains { $0.to == .error })
        XCTAssertEqual(machine.state, .idle)
    }

    func testChatNetworkErrorIsReportedNotCrashed() async {
        let chat = FakeChatProvider(.failure(ChatError.missingAPIKey))
        let secretary = makeSecretary(projects: [project], chat: chat)

        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertTrue(machine.history.contains { $0.to == .error })
        XCTAssertTrue(secretary.transcript.last?.text.contains("API key") ?? false)
    }

    func testSlashModelSwitchesModelWithoutHittingTheNetwork() {
        let chat = FakeChatProvider(.events([]))
        let secretary = makeSecretary(projects: [project], chat: chat)

        secretary.submit("/model claude-opus-4-8")

        XCTAssertEqual(secretary.model, .opus48)
        XCTAssertEqual(chat.callCount, 0)
        XCTAssertTrue(secretary.transcript.last?.text.contains("claude-opus-4-8") ?? false)
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

        guard case .approval = secretary.pendingDecision else {
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
