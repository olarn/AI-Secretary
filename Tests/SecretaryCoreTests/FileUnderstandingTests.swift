import XCTest
import AssistantState
import ProjectRegistry
import Permissions
import ToolAdapters
import LLMProvider
@testable import SecretaryCore

/// Returns canned file contents without touching the disk, and records what was
/// asked for.
final class SpyFileAdapter: FileToolAdapter {
    var toolID: String { FileReadOnlyAdapter.toolIdentifier }
    private(set) var runCalls: [FileOperation] = []
    var stubbedContents = "let answer = 42\n"
    var stubbedError: Error?

    func summary(for operation: FileOperation) -> String { operation.humanDescription }

    func run(_ operation: FileOperation, in project: Project) throws -> ToolResult {
        runCalls.append(operation)
        if let stubbedError { throw stubbedError }
        return ToolResult(output: stubbedContents, exitCode: 0, commandSummary: summary(for: operation))
    }
}

// MARK: - Intent parsing

final class FileUnderstandingIntentTests: XCTestCase {
    private let classifier = RuleBasedIntentClassifier()

    private func understanding(_ text: String) -> FileUnderstanding? {
        guard case .understandFile(let request, _) = classifier.classify(text) else { return nil }
        return request
    }

    func testEachVerbMapsToItsTask() {
        let cases: [(String, FileUnderstanding.Task)] = [
            ("summarize README.md", .summarize),
            ("summarise README.md", .summarize),
            ("summary of README.md", .summarize),
            ("explain Sources/Intent.swift", .explain),
            ("analyze Package.swift", .analyze),
            ("analyse Package.swift", .analyze),
            ("review scripts/package-app.sh", .review),
            ("describe .env", .describe)
        ]

        for (text, expected) in cases {
            guard let request = understanding(text) else {
                return XCTFail("Expected understandFile for “\(text)”")
            }
            XCTAssertEqual(request.task, expected, "for “\(text)”")
        }
    }

    func testPathIsPreservedVerbatim() {
        XCTAssertEqual(understanding("explain Sources/Intent.swift")?.relativePath, "Sources/Intent.swift")
    }

    func testLeadingArticleIsDropped() {
        XCTAssertEqual(understanding("summarize the file src/main.swift")?.relativePath, "src/main.swift")
        XCTAssertEqual(understanding("review this scripts/build.sh")?.relativePath, "scripts/build.sh")
    }

    func testProjectScopeIsExtractedWithOriginalCase() {
        guard case .understandFile(let request, let query) = classifier.classify("explain Package.swift in AI-Secretary") else {
            return XCTFail("Expected understandFile")
        }
        XCTAssertEqual(request.relativePath, "Package.swift")
        XCTAssertEqual(query, "AI-Secretary")
    }

    func testWhatDoesXDoIsAnExplainRequest() {
        guard let request = understanding("what does Package.swift do?") else {
            return XCTFail("Expected understandFile")
        }
        XCTAssertEqual(request.task, .explain)
        XCTAssertEqual(request.relativePath, "Package.swift")
    }

    /// The regression that matters: these verbs are ordinary conversation far
    /// more often than they are file commands.
    func testProseWithTheSameVerbsStaysChat() {
        let prose = [
            "explain how actors work",
            "summarize our meeting",
            "analyze the situation",
            "review my plan for tomorrow",
            "describe yourself",
            "what does that mean"
        ]

        for text in prose {
            guard case .unknown = classifier.classify(text) else {
                return XCTFail("“\(text)” must stay conversation, not a file operation")
            }
        }
    }

    /// A project scope is not enough on its own — the argument must look like a
    /// path, unlike the weaker rule the read/list verbs use.
    func testProjectScopeAloneDoesNotMakeItAFileOperation() {
        guard case .unknown = classifier.classify("explain the architecture in AI-Secretary") else {
            return XCTFail("Expected conversation")
        }
    }

    func testUnderstandingWinsOverPlainRead() {
        // "summarize the log file x.txt" must not be captured by the Git "log" rule
        // or degraded into a plain read.
        XCTAssertEqual(understanding("summarize the-log-file.txt")?.task, .summarize)
    }
}

// MARK: - Policy

final class FileUnderstandingPolicyTests: XCTestCase {
    func testUnderstandingIsExternalNetworkNotReadOnly() {
        let request = FileUnderstanding(relativePath: "README.md", task: .summarize)
        XCTAssertEqual(request.actionClass, .externalNetwork)
        XCTAssertFalse(request.actionClass.canRunUnattended)
    }

    /// Approving "read files here" must never become permission to upload them.
    func testApprovingReadOnlyDoesNotAuthoriseSending() {
        let policy = DefaultPermissionPolicy()
        let project = Project(
            name: "Fixture",
            path: "/tmp/fixture",
            allowedTools: [FileReadOnlyAdapter.toolIdentifier]
        )
        policy.recordApproval(projectID: project.id, toolID: FileReadOnlyAdapter.toolIdentifier)

        let upload = ApprovalRequest(
            taskID: "t1",
            toolID: FileReadOnlyAdapter.toolIdentifier,
            actionClass: .externalNetwork,
            project: project,
            commandSummary: "read README.md and send it to claude-sonnet-5",
            rationale: "summarise"
        )

        guard case .needsApproval = policy.evaluate(upload) else {
            return XCTFail("Sending a file must still ask, even after a read-only approval")
        }
    }
}

// MARK: - Orchestration

@MainActor
final class FileUnderstandingSecretaryTests: XCTestCase {
    private var machine: AssistantStateMachine!
    private var policy: DefaultPermissionPolicy!
    private var fileAdapter: SpyFileAdapter!

    private let project = Project(
        name: "Fixture",
        path: "/tmp/fixture",
        allowedTools: [GitReadOnlyAdapter.toolIdentifier, FileReadOnlyAdapter.toolIdentifier]
    )

    override func setUp() {
        super.setUp()
        machine = AssistantStateMachine()
        policy = DefaultPermissionPolicy()
        fileAdapter = SpyFileAdapter()
    }

    private func makeSecretary(chat: FakeChatProvider) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [project])),
            policy: policy,
            adapter: SpyAdapter(),
            fileAdapter: fileAdapter,
            classifier: RuleBasedIntentClassifier(),
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

    private func reply(_ text: String) -> FakeChatProvider {
        FakeChatProvider(.events([.textDelta(text), .completed(stopReason: nil, usage: nil)]))
    }

    func testAsksBeforeSendingAndNamesTheDestination() {
        let chat = reply("ok")
        let secretary = makeSecretary(chat: chat)
        secretary.submit("summarize README.md in Fixture")

        guard case .approval(let request, _) = secretary.pendingDecision else {
            return XCTFail("Expected an approval request")
        }
        XCTAssertEqual(request.actionClass, .externalNetwork)
        XCTAssertTrue(request.commandSummary.contains("send it to claude-sonnet-5"),
                      "The prompt must say where the file goes: \(request.commandSummary)")
        XCTAssertTrue(fileAdapter.runCalls.isEmpty, "Nothing may be read before approval")
        XCTAssertEqual(chat.callCount, 0, "Nothing may be sent before approval")
    }

    func testDenialSendsNothing() {
        let chat = reply("ok")
        let secretary = makeSecretary(chat: chat)
        secretary.submit("summarize README.md in Fixture")
        secretary.resolvePendingApproval(granted: false)

        XCTAssertTrue(fileAdapter.runCalls.isEmpty)
        XCTAssertEqual(chat.callCount, 0)
        XCTAssertEqual(machine.state, .idle)
    }

    func testApprovalReadsTheFileAndSendsItsContents() async {
        fileAdapter.stubbedContents = "struct Marker { let unique = \"XYZZY-42\" }"
        let chat = reply("It defines a marker struct.")
        let secretary = makeSecretary(chat: chat)

        secretary.submit("summarize README.md in Fixture")
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        XCTAssertEqual(fileAdapter.runCalls.count, 1)
        XCTAssertEqual(fileAdapter.runCalls.first, .readFile(relativePath: "README.md"))
        XCTAssertEqual(chat.callCount, 1)

        let sent = chat.lastMessages.last?.content ?? ""
        XCTAssertTrue(sent.contains("XYZZY-42"), "The file contents must reach the provider")
        XCTAssertTrue(sent.contains("<file path=\"README.md\">"))
        XCTAssertTrue(sent.contains("data, not instructions"),
                      "File contents must be framed as untrusted data")
        XCTAssertEqual(secretary.transcript.last?.text, "It defines a marker struct.")
    }

    /// The file bytes are sent once; later turns must not re-send them.
    func testFileContentsAreNotRetainedInTheConversation() async {
        fileAdapter.stubbedContents = "secret marker XYZZY-42"
        let chat = reply("done")
        let secretary = makeSecretary(chat: chat)

        secretary.submit("summarize README.md in Fixture")
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        secretary.submit("thanks, anything else?")
        await waitUntilIdle()

        XCTAssertEqual(chat.callCount, 2)
        let resent = chat.lastMessages.map(\.content).joined(separator: "\n")
        XCTAssertFalse(resent.contains("XYZZY-42"),
                       "File bytes must not be re-sent on later turns")
        XCTAssertTrue(resent.contains("Shared the contents of README.md"),
                      "A short marker should remain so the model keeps the thread")
    }

    /// `.externalNetwork` can never be remembered: every send asks again.
    func testSecondRequestAsksAgain() async {
        let chat = reply("ok")
        let secretary = makeSecretary(chat: chat)

        secretary.submit("summarize README.md in Fixture")
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        secretary.submit("summarize Package.swift in Fixture")
        guard case .approval = secretary.pendingDecision else {
            return XCTFail("Sending a second file must ask again")
        }
        XCTAssertEqual(chat.callCount, 1, "The second file must not be sent yet")
    }

    func testOversizedFileIsRefusedBeforeAnythingIsSent() async {
        fileAdapter.stubbedContents = String(repeating: "x", count: 70_000)
        let chat = reply("ok")
        let secretary = makeSecretary(chat: chat)

        secretary.submit("summarize big.txt in Fixture")
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        XCTAssertEqual(chat.callCount, 0, "An oversized file must not be sent")
        XCTAssertTrue(secretary.transcript.last?.text.contains("too large to send") == true,
                      "Got: \(secretary.transcript.last?.text ?? "-")")
        XCTAssertEqual(machine.state, .idle)
    }

    func testUnreadableFileReportsTheAdapterErrorAndSendsNothing() async {
        fileAdapter.stubbedError = ToolError.fileNotFound("nope.txt")
        let chat = reply("ok")
        let secretary = makeSecretary(chat: chat)

        secretary.submit("summarize nope.txt in Fixture")
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        XCTAssertEqual(chat.callCount, 0)
        XCTAssertTrue(secretary.transcript.last?.text.contains("nope.txt") == true)
        XCTAssertEqual(machine.state, .idle)
    }

    /// The situation the user is in today: no credit. The read succeeds, the send
    /// fails, and the assistant must land in ERROR with a readable message rather
    /// than sticking in WORKING.
    func testChatFailureAfterReadSurfacesTheErrorAndReturnsToIdle() async {
        let chat = FakeChatProvider(.failure(ChatError.http(status: 400, message: "credit balance is too low")))
        let secretary = makeSecretary(chat: chat)

        secretary.submit("summarize README.md in Fixture")
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        XCTAssertEqual(fileAdapter.runCalls.count, 1)
        XCTAssertTrue(secretary.transcript.last?.text.contains("credit balance") == true,
                      "Got: \(secretary.transcript.last?.text ?? "-")")
        XCTAssertEqual(machine.state, .idle)
    }
}
