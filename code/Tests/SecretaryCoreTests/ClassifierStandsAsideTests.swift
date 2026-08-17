import FunctionalCore
import XCTest
import AssistantState
import Permissions
import ProjectRegistry
import ToolAdapters
@testable import SecretaryCore

/// A backend that can open the folder itself is not routed through the keyword
/// classifier.
///
/// The rules were written for a bare API with no hands. Against Claude Code
/// they cost correctness (the adapter's answer never enters the model's
/// session, so a follow-up question has nothing to refer to) and consistency
/// (the keywords are English-only, so the same request took different paths
/// depending on which language it was typed in).
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

    /// Each message in a loop needs its own spies, or the counts from the
    /// previous one are still on them and every assertion after the first is
    /// comparing against a running total.
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

    /// The messages that used to be intercepted. Every one of them is now the
    /// model's to answer, and no adapter is touched.
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

    /// Sprint 15.2's paragraph, on the agent path. It reached the model before
    /// this sprint only because the guards sent it there; now nothing else
    /// could have happened to it.
    func testProseReachesTheModelTooAndAsksForNoProject() async {
        provider.hasWorkspaceTools = true
        let secretary = makeSecretary()
        // swiftlint:disable:next line_length
        secretary.submit("Alpha Capital Group is a company specializing in non-performing asset management through its operating subsidiaries, Alpha Capital Asset Management Co., Ltd. (Alpha) and Wireless Asset Management Co., Ltd. (WAMC). The group manages non-performing loan (NPL) portfolios and non-performing assets (NPA), including property sales, borrower follow-up, collection, legal status, collateral management, customer enquiries, and related service processes")
        await waitUntilIdle()

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(secretary.pendingDecision, .none(), "nothing to approve, nothing to choose")
    }

    /// The fallback is untouched. A bare chat model genuinely cannot look, so
    /// the classifier and the adapters are the only way those requests get
    /// answered at all.
    ///
    /// The card is the evidence: the tool path stops there before the adapter
    /// is ever asked to run, so a card at all means the words were read as a
    /// command rather than as chat.
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

    /// Detection has usually not finished when the app opens, so the first
    /// message can take the fallback path and a later one cannot. Deliberate,
    /// and pinned here so it reads as a decision rather than a flake.
    func testTheAnswerFollowsTheBackendWhenDetectionFinishesMidSession() async {
        provider.hasWorkspaceTools = false
        let secretary = makeSecretary()
        secretary.submit("status in AI-Secretary")
        await waitUntilIdle()
        guard case .approval = secretary.pendingDecision.toOptional() else {
            return XCTFail("before detection this must be classified as a command")
        }
        XCTAssertEqual(provider.callCount, 0)

        // Deny, so the pending card is cleared and the next message is free to
        // take its own path.
        secretary.resolvePendingApproval(answer: .deny)
        await waitUntilIdle()

        provider.hasWorkspaceTools = true
        secretary.submit("status in AI-Secretary")
        await waitUntilIdle()

        XCTAssertEqual(secretary.pendingDecision, .none(), "after detection: not classified")
        XCTAssertEqual(provider.callCount, 1, "it went to the model instead")
    }

    /// `help` is answered by the app itself, before any of this. It is local,
    /// so which backend is attached changes what it *says* but not who answers.
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

    // MARK: - What help promises

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
