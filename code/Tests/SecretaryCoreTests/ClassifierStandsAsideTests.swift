import FunctionalCore
import XCTest
import AssistantState
import Permissions
import ProjectRegistry
import ToolAdapters
@testable import SecretaryCore

@MainActor
final class ClassifierStandsAsideTests: XCTestCase {
    private var machine = AssistantStateMachine()
    private var provider = SpyWorkspaceProvider()
    private var adapter = SpyAdapter()
    private var fileAdapter = SpyFileAdapter()

    override func setUp() {
        super.setUp()
        freshCollaborators()
    }

    private func freshCollaborators() {
        machine = AssistantStateMachine()
        provider = SpyWorkspaceProvider()
        adapter = SpyAdapter()
        fileAdapter = SpyFileAdapter()
    }

    private let project = Project(
        name: "AI-Secretary",
        path: "/tmp/ai-secretary",
        allowedTools: [
            GitReadOnlyAdapter.toolIdentifier,
            FileReadOnlyAdapter.toolIdentifier,
            Secretary.claudeCodeToolID
        ]
    )

    private func makeSecretary() -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [project])),
            adapter: adapter,
            fileAdapter: fileAdapter,
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: provider
        )
    }

    private func waitUntilIdle(timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while machine.state != .idle && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private let wouldHaveBeenCommands = [
        "read README.md in AI-Secretary",
        "status in AI-Secretary",
        "list files in AI-Secretary",
        "summarize README.md in AI-Secretary"
    ]

    func testWithWorkspaceToolsEveryMessageReachesTheModel() async {
        for text in wouldHaveBeenCommands {
            freshCollaborators()
            provider.hasWorkspaceTools = true
            let secretary = makeSecretary()
            secretary.submit(text)
            await waitUntilIdle()

            XCTAssertEqual(provider.callCount, 1, "should have gone to the model: \(text)")
            XCTAssertEqual(adapter.runCalls.count, 0, "git adapter must not run: \(text)")
            XCTAssertEqual(fileAdapter.runCalls.count, 0, "file adapter must not run: \(text)")
            XCTAssertEqual(
                secretary.pendingDecision, .none(),
                "and must not stop to ask about a tool it isn't using: \(text)"
            )
        }
    }

    func testProseReachesTheModelTooAndAsksForNoProject() async {
        provider.hasWorkspaceTools = true
        let secretary = makeSecretary()
        secretary.submit("Alpha Capital Group is a company specializing in non-performing asset management through its operating subsidiaries, Alpha Capital Asset Management Co., Ltd. (Alpha) and Wireless Asset Management Co., Ltd. (WAMC). The group manages non-performing loan (NPL) portfolios and non-performing assets (NPA), including property sales, borrower follow-up, collection, legal status, collateral management, customer enquiries, and related service processes")
        await waitUntilIdle()

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(secretary.pendingDecision, .none(), "nothing to approve, nothing to choose")
    }

    func testWithoutWorkspaceToolsTheClassifierStillRuns() async {
        provider.hasWorkspaceTools = false
        let secretary = makeSecretary()
        secretary.submit("status in AI-Secretary")
        await waitUntilIdle()

        guard case .approval(let request, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected the tool path, got: \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(request.toolID, GitReadOnlyAdapter.toolIdentifier)
        XCTAssertEqual(provider.callCount, 0, "and does not spend a model turn on it")
    }

    func testTheAnswerFollowsTheBackendWhenDetectionFinishesMidSession() async {
        provider.hasWorkspaceTools = false
        let secretary = makeSecretary()
        secretary.submit("status in AI-Secretary")
        await waitUntilIdle()
        guard case .approval = secretary.pendingDecision.toOptional() else {
            return XCTFail("before detection this must be classified as a command")
        }
        XCTAssertEqual(provider.callCount, 0)

        secretary.resolvePendingApproval(answer: .deny)
        await waitUntilIdle()

        provider.hasWorkspaceTools = true
        secretary.submit("status in AI-Secretary")
        await waitUntilIdle()

        XCTAssertEqual(secretary.pendingDecision, .none(), "after detection: not classified")
        XCTAssertEqual(provider.callCount, 1, "it went to the model instead")
    }

    func testHelpIsStillAnsweredLocally() async {
        provider.hasWorkspaceTools = true
        let secretary = makeSecretary()
        secretary.submit("help")
        await waitUntilIdle()

        XCTAssertEqual(provider.callCount, 0, "help never costs a turn")
        XCTAssertTrue(
            secretary.transcript.contains { $0.text.contains("/model") },
            "and still lists the slash commands"
        )
    }

    func testHelpDoesNotTeachTypedCommandsOnTheAgentPath() {
        let agent = SecretaryPrompt.helpText(workspaceTools: true)
        XCTAssertFalse(agent.contains("status — working tree status"),
                       "the keyword rules no longer run on this path")
        XCTAssertFalse(agent.contains("Add “in <project>”"))
        XCTAssertTrue(agent.contains("/model"), "slash commands are handled in the app either way")
    }

    func testHelpStillTeachesThemOnTheFallbackPath() {
        let fallback = SecretaryPrompt.helpText(workspaceTools: false)
        XCTAssertTrue(fallback.contains("status — working tree status"))
        XCTAssertTrue(fallback.contains("Add “in <project>”"))
        XCTAssertTrue(fallback.contains("/model"))
    }
}
