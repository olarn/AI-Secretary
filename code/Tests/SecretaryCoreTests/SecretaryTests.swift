import FunctionalCore
import XCTest
import AssistantState
import ProjectRegistry
import Permissions
import ToolAdapters
import LLMProvider
@testable import SecretaryCore

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

final class FakeChatProvider: ChatProvider, @unchecked Sendable {
    enum Script {
        case events([ChatStreamEvent])
        case failure(ChatError)
    }

    private let script: Script
    private(set) var callCount = 0
    private(set) var lastMessages: [ChatMessage] = []
    private(set) var lastModelWhereNilAlsoMeansInherit: ChatModel?
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
        lastModelWhereNilAlsoMeansInherit = model.toOptional()
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
        let resolved = outside.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertTrue(
            request.commandSummary.contains(resolved),
            "The card has to name where the reading happens. Got: \(request.commandSummary)"
        )
        XCTAssertTrue(secretary.activeWatches.isEmpty, "nothing is watched before the answer")
    }

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

    func testAnApprovedOutsideFolderKeepsResolvingOnEveryLook() async throws {
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
        await secretary.tickWatch()

        XCTAssertTrue(
            secretary.transcript.last?.text.contains("new.txt") ?? false,
            "The look after approval has to see the folder. Got: \(secretary.transcript.last?.text ?? "nothing")"
        )
    }

    func testAWatchStartedWithAnInstructionHandsTheChangeToTheModel() async throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let chat = FakeChatProvider(.events([
            .textDelta("Watching it now."),
            .textDelta("\n\n```watch\n\(outside.path)\n```"),
            .completed(stopReason: .none(), usage: .none())
        ]))
        let secretary = makeSecretary(
            projects: [Project(name: "Registered", path: "/tmp/registered")],
            chat: chat
        )
        secretary.submit("Watch \(outside.path) and do what any file that lands there says")
        await waitUntilIdle()
        secretary.resolvePendingApproval(granted: true)

        XCTAssertEqual(secretary.activeWatches.count, 1)
        XCTAssertTrue(
            secretary.activeWatches.first?.instruction.contains("do what any file that lands there says") ?? false,
            "The watch has to remember what it was started for. Got: \(String(describing: secretary.activeWatches.first?.instruction))"
        )

        try "hello".write(
            to: outside.appendingPathComponent("new.txt"),
            atomically: true,
            encoding: .utf8
        )
        await secretary.tickWatch()

        XCTAssertTrue(
            secretary.transcript.contains { $0.text.contains("new.txt") },
            "The person is still told by the app itself."
        )
        await waitUntilIdle()
        XCTAssertTrue(
            chat.lastMessages.contains { $0.content.contains("[Folder watch]") },
            """
            The model has to be handed the change. \
            Got: \(chat.lastMessages.map(\.content).joined(separator: " | "))
            """
        )
        XCTAssertTrue(
            chat.lastMessages.contains { $0.content.contains("do what any file that lands there says") },
            "…with the standing instruction quoted back."
        )
    }

    func testATypedWatchStillOnlyReports() async throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let secretary = makeSecretary(projects: [Project(name: "Registered", path: "/tmp/registered")])
        secretary.submit("/watch \(outside.path)")
        secretary.resolvePendingApproval(granted: true)
        XCTAssertEqual(secretary.activeWatches.first?.instruction, "")

        try "hello".write(
            to: outside.appendingPathComponent("new.txt"),
            atomically: true,
            encoding: .utf8
        )
        await secretary.tickWatch()

        XCTAssertFalse(
            secretary.transcript.contains { $0.text.contains("[Folder watch]") },
            "Nobody asked for anything to happen."
        )
    }

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

    func testAnUninheritedModelOrEffortReadsAsDefaultNotUnknown() {
        let secretary = makeSecretary(projects: [project])

        XCTAssertEqual(secretary.effectiveModelName, "Default")
        XCTAssertEqual(secretary.effectiveEffortName, "Default")
        XCTAssertTrue(secretary.isModelInherited)
        XCTAssertTrue(secretary.isEffortInherited)
    }

    func testAChosenModelStillShowsItsOwnName() {
        let secretary = makeSecretary(projects: [project])

        secretary.selectModel(.some(.opus48))

        XCTAssertEqual(secretary.effectiveModelName, ChatModel.opus48.displayName)
        XCTAssertFalse(secretary.isModelInherited)
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
