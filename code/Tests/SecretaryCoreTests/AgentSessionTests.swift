import XCTest
import AssistantState
import ProjectRegistry
import Permissions
import ToolAdapters
import LLMProvider
@testable import SecretaryCore

/// A chat provider that is also directory-scoped, so we can see what the
/// Secretary told it before a turn.
final class SpyWorkspaceProvider: ChatProvider, WorkspaceScopedProvider, @unchecked Sendable {
    private(set) var preparedDirectories: [URL?] = []
    private(set) var preparedTools: [[String]?] = []
    private(set) var callCount = 0
    private(set) var lastMessages: [ChatMessage] = []
    private(set) var lastSystem: String?
    private(set) var resetCount = 0
    var hasWorkspaceTools = true

    private(set) var preparedExtras: [[URL]] = []

    func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?) {
        preparedDirectories.append(workingDirectory)
        preparedExtras.append(additionalDirectories)
        preparedTools.append(allowedTools)
    }

    func resetConversation() { resetCount += 1 }

    func stream(
        messages: [ChatMessage],
        model: ChatModel,
        effort: Effort,
        maxTokens: Int,
        system: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        callCount += 1
        lastMessages = messages
        lastSystem = system
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("ok"))
            continuation.yield(.completed(stopReason: nil, usage: nil))
            continuation.finish()
        }
    }
}

@MainActor
final class AgentSessionTests: XCTestCase {
    private var machine: AssistantStateMachine!
    private var provider: SpyWorkspaceProvider!
    private var store: InMemoryProjectStore!
    private var registry: ProjectRegistry!

    private let projectPath = "/tmp/agent-fixture"

    override func setUp() {
        super.setUp()
        machine = AssistantStateMachine()
        provider = SpyWorkspaceProvider()
    }

    private func makeSecretary(projects: [Project]) -> Secretary {
        store = InMemoryProjectStore(projects: projects)
        registry = ProjectRegistry(store: store)
        return Secretary(
            stateMachine: machine,
            registry: registry,
            policy: DefaultPermissionPolicy(),
            adapter: SpyAdapter(),
            fileAdapter: SpyFileAdapter(),
            classifier: RuleBasedIntentClassifier(),
            audit: AuditLog(),
            chatProvider: provider
        )
    }

    private func project(grantingAgent: Bool) -> Project {
        Project(
            name: "Fixture",
            path: projectPath,
            allowedTools: grantingAgent
                ? [FileReadOnlyAdapter.toolIdentifier, Secretary.claudeCodeToolID]
                : [FileReadOnlyAdapter.toolIdentifier]
        )
    }

    private func waitUntilIdle(timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while machine.state != .idle && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - Asking before working in a project

    func testFirstMessageInAnUngrantedProjectAsksBeforeRunningAnything() {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("what does this project do?")

        guard case .approval(let request, let operation) = secretary.pendingDecision else {
            return XCTFail("Expected an approval request")
        }
        XCTAssertEqual(request.toolID, Secretary.claudeCodeToolID)
        XCTAssertEqual(operation, .startAgent(prompt: "what does this project do?"))
        XCTAssertEqual(provider.callCount, 0, "Nothing may run before approval")
        XCTAssertTrue(provider.preparedDirectories.isEmpty)
    }

    /// The prompt has to say what the grant actually covers, because it is
    /// approve-once rather than per-message.
    func testTheApprovalPromptSaysItRunsOnTheUsersClaudeCodeAccount() {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("hello")

        let prompt = secretary.transcript.last?.text ?? ""
        XCTAssertTrue(prompt.contains("Claude Code"), "Got: \(prompt)")
        XCTAssertTrue(prompt.contains("Fixture"), "Should name the project. Got: \(prompt)")
    }

    func testApprovingPersistsTheGrantAndRunsTheOriginalMessage() async throws {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("summarise this repo please")
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        XCTAssertEqual(provider.callCount, 1, "The interrupted message should run after approval")
        XCTAssertEqual(provider.lastMessages.last?.content, "summarise this repo please")
        XCTAssertEqual(provider.preparedDirectories.last??.path, projectPath)

        let saved = try XCTUnwrap(try store.load().first)
        XCTAssertTrue(saved.allowedTools.contains(Secretary.claudeCodeToolID),
                      "The grant must survive a relaunch")
    }

    func testDenyingRunsNothingAndDoesNotPersistAGrant() async throws {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("hello")
        secretary.resolvePendingApproval(granted: false)

        XCTAssertEqual(provider.callCount, 0)
        let saved = try XCTUnwrap(try store.load().first)
        XCTAssertFalse(saved.allowedTools.contains(Secretary.claudeCodeToolID))
    }

    func testAnAlreadyGrantedProjectRunsWithoutAsking() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertNil(secretary.pendingDecision)
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(provider.preparedDirectories.last??.path, projectPath)
    }

    func testAskingOnlyHappensOncePerProject() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("first")
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        secretary.submit("second")
        await waitUntilIdle()

        XCTAssertNil(secretary.pendingDecision, "The second message must not ask again")
        XCTAssertEqual(provider.callCount, 2)
    }

    // MARK: - Telling the backend what it can do

    /// Reported from real use: asked to summarise a project, the assistant said
    /// it couldn't see the contents and asked the user to paste them, then told
    /// them to type `list files in <project>`. The system prompt was the
    /// chat-only one, which says the model cannot run commands itself.
    func testAnAgentBackendIsNeverToldItCannotAct() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("สรุปเนื้อหาให้ฟังหน่อย")
        await waitUntilIdle()

        let prompt = try? XCTUnwrap(provider.lastSystem)
        XCTAssertFalse(prompt?.contains("cannot run commands") == true,
                       "Got: \(prompt ?? "-")")
        XCTAssertFalse(prompt?.contains("tell the \nuser the exact command") == true)
        XCTAssertTrue(prompt?.contains("look for yourself") == true,
                      "It should be told to open files itself. Got: \(prompt ?? "-")")
    }

    func testTheAgentPromptNamesTheProjectItIsStandingIn() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertTrue(provider.lastSystem?.contains("Fixture") == true,
                      "Got: \(provider.lastSystem ?? "-")")
    }

    /// The old prompt is still right for a plain chat model with no tools.
    func testAChatOnlyBackendKeepsTheAdviceToTypeCommands() async {
        provider.hasWorkspaceTools = false
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertTrue(provider.lastSystem?.contains("cannot run commands") == true,
                      "Got: \(provider.lastSystem ?? "-")")
    }

    // MARK: - Working with no project

    /// Claude Code always runs somewhere. With no project registered it must not
    /// inherit whatever directory the app launched from.
    func testWithNoProjectItRunsInAScratchDirectoryNotTheLaunchDirectory() async {
        let secretary = makeSecretary(projects: [])
        secretary.submit("hello")
        await waitUntilIdle()

        let directory = try? XCTUnwrap(provider.preparedDirectories.last ?? nil)
        XCTAssertEqual(directory?.lastPathComponent, "scratch")
        XCTAssertNotEqual(directory?.path, FileManager.default.currentDirectoryPath)
        XCTAssertEqual(provider.callCount, 1)
    }

    // MARK: - More than one project

    /// The point of the feature: with two approved projects, both are reachable
    /// in one turn so a question spanning them doesn't need the user to switch.
    func testEveryApprovedProjectIsOpenAlongsideThePrimaryOne() async {
        let other = Project(name: "Other", path: "/tmp/other",
                            allowedTools: [Secretary.claudeCodeToolID])
        let secretary = makeSecretary(projects: [project(grantingAgent: true), other])
        secretary.submit("compare the two projects")
        await waitUntilIdle()

        XCTAssertEqual(provider.preparedDirectories.last??.path, projectPath)
        XCTAssertEqual(provider.preparedExtras.last?.map(\.path), ["/tmp/other"])
    }

    /// Only approved folders may be opened — the per-project grant is the gate.
    func testAnUnapprovedProjectIsNotOpened() async {
        let secret = Project(name: "Secret", path: "/tmp/secret", allowedTools: [])
        let secretary = makeSecretary(projects: [project(grantingAgent: true), secret])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertEqual(provider.preparedExtras.last, [], "An unapproved folder must stay closed")
    }

    func testTheAgentPromptMentionsTheOtherOpenProjects() async {
        let other = Project(name: "Other", path: "/tmp/other",
                            allowedTools: [Secretary.claudeCodeToolID])
        let secretary = makeSecretary(projects: [project(grantingAgent: true), other])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertTrue(provider.lastSystem?.contains("Other") == true,
                      "Got: \(provider.lastSystem ?? "-")")
    }

    /// Several projects, none approved yet: guessing would be wrong, so ask.
    func testSeveralUnapprovedProjectsAskWhichToStartIn() {
        let secretary = makeSecretary(projects: [
            project(grantingAgent: false),
            Project(name: "Other", path: "/tmp/other", allowedTools: [])
        ])
        secretary.submit("hello")

        guard case .projectChoice(let candidates, let operation) = secretary.pendingDecision else {
            return XCTFail("Expected a project choice, got: \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(operation, .startAgent(prompt: "hello"))
        XCTAssertEqual(provider.callCount, 0)
    }

    /// Choosing an unapproved project still has to ask before running.
    func testChoosingAProjectThenAsksToApproveIt() {
        let secretary = makeSecretary(projects: [
            project(grantingAgent: false),
            Project(name: "Other", path: "/tmp/other", allowedTools: [])
        ])
        secretary.submit("hello")
        guard case .projectChoice(let candidates, _) = secretary.pendingDecision else {
            return XCTFail("Expected a project choice")
        }
        secretary.choose(project: candidates[0])

        guard case .approval(let request, _) = secretary.pendingDecision else {
            return XCTFail("Expected an approval request after choosing")
        }
        XCTAssertEqual(request.toolID, Secretary.claudeCodeToolID)
        XCTAssertEqual(provider.callCount, 0)
    }
}

// MARK: - Registry grants

final class ProjectGrantTests: XCTestCase {
    func testGrantAddsTheToolAndPersistsIt() throws {
        let project = Project(name: "P", path: "/tmp/p", allowedTools: ["a"])
        let store = InMemoryProjectStore(projects: [project])
        let registry = ProjectRegistry(store: store)

        XCTAssertTrue(try registry.grant(tool: "b", to: project.id))
        XCTAssertEqual(try store.load().first?.allowedTools, ["a", "b"])
    }

    func testGrantingTwiceIsANoOp() throws {
        let project = Project(name: "P", path: "/tmp/p", allowedTools: ["a"])
        let store = InMemoryProjectStore(projects: [project])
        let registry = ProjectRegistry(store: store)

        XCTAssertTrue(try registry.grant(tool: "b", to: project.id))
        XCTAssertFalse(try registry.grant(tool: "b", to: project.id))
        XCTAssertEqual(try store.load().first?.allowedTools, ["a", "b"])
    }

    func testGrantingToAnUnknownProjectDoesNothing() throws {
        let registry = ProjectRegistry(store: InMemoryProjectStore(projects: []))
        XCTAssertFalse(try registry.grant(tool: "b", to: UUID()))
    }
}
