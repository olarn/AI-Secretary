import FunctionalCore
import XCTest
import AssistantState
import Permissions
import ProjectRegistry
import ToolAdapters
import LLMProvider
@testable import SecretaryCore

@MainActor
final class BrowserAccessTests: XCTestCase {
    private var machine: AssistantStateMachine!
    private var provider: SpyWorkspaceProvider!
    private var preference: InMemoryBrowserPreference!

    private let projectPath = "/tmp/browser-fixture"

    override func setUp() {
        super.setUp()
        machine = AssistantStateMachine()
        provider = SpyWorkspaceProvider()
        preference = InMemoryBrowserPreference()
    }

    private func makeSecretary(projects: [Project]? = nil) -> Secretary {
        let project = Project(
            name: "Fixture",
            path: projectPath,
            allowedTools: [FileReadOnlyAdapter.toolIdentifier, Secretary.claudeCodeToolID]
        )
        return Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: projects ?? [project])),
            adapter: SpyAdapter(),
            fileAdapter: SpyFileAdapter(),
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            activityPreference: InMemoryActivityPreference(),
            browserPreference: preference,
            chatProvider: provider
        )
    }

    private func waitUntilIdle(timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while machine.state != .idle && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func lastAllowedTools() -> [String] {
        provider.preparedTools.compactMap { $0 }.last ?? []
    }

    func testTheBrowserStartsDisconnected() {
        XCTAssertFalse(makeSecretary().browserEnabled)
    }

    func testARememberedChoiceIsAppliedWhenTheAppStarts() {
        preference.browserEnabled = true
        let secretary = makeSecretary()
        XCTAssertTrue(secretary.browserEnabled)
        XCTAssertEqual(provider.browserEnabledCalls, [true])
    }

    func testConnectingIsRememberedAndPassedToTheBackend() {
        let secretary = makeSecretary()
        secretary.setBrowserEnabled(true)
        XCTAssertTrue(preference.browserEnabled)
        XCTAssertEqual(provider.browserEnabledCalls.last, true)
    }

    func testConnectingIsAnnouncedInTheChat() {
        let secretary = makeSecretary()
        secretary.setBrowserEnabled(true)
        let said = secretary.transcript.last?.text ?? ""
        XCTAssertTrue(said.lowercased().contains("browser"), "Got: \(said)")
        XCTAssertTrue(said.lowercased().contains("password"), "Should address the obvious worry. Got: \(said)")
    }

    func testDisconnectingIsAnnouncedToo() {
        let secretary = makeSecretary()
        secretary.setBrowserEnabled(true)
        secretary.setBrowserEnabled(false)
        XCTAssertFalse(preference.browserEnabled)
        XCTAssertTrue((secretary.transcript.last?.text ?? "").contains("disconnected"))
    }

    func testReadingToolsAreOfferedOnlyWhileTheBrowserIsConnected() async {
        let secretary = makeSecretary()
        secretary.submit("what does this page say?")
        await waitUntilIdle()
        XCTAssertFalse(
            lastAllowedTools().contains(BrowserTools.rule(for: "read_page")),
            "A disconnected browser must not pre-approve its tools"
        )

        secretary.setBrowserEnabled(true)
        secretary.submit("and now?")
        await waitUntilIdle()
        XCTAssertTrue(lastAllowedTools().contains(BrowserTools.rule(for: "read_page")))
        XCTAssertTrue(lastAllowedTools().contains(BrowserTools.rule(for: "get_page_text")))
    }

    func testActingOnAPageIsNeverPreApproved() async {
        let secretary = makeSecretary()
        secretary.setBrowserEnabled(true)
        secretary.submit("read this")
        await waitUntilIdle()

        let allowed = lastAllowedTools()
        for tool in ["navigate", "form_input", "computer", "javascript_tool", "file_upload"] {
            XCTAssertFalse(
                allowed.contains(BrowserTools.rule(for: tool)),
                "\(tool) must require approval"
            )
        }
    }

    func testConnectingTheBrowserKeepsTheExistingTools() async {
        let secretary = makeSecretary()
        secretary.setBrowserEnabled(true)
        secretary.submit("hello")
        await waitUntilIdle()
        XCTAssertTrue(lastAllowedTools().contains("Read"))
        XCTAssertTrue(lastAllowedTools().contains("Grep"))
    }

    func testABlockedBrowserActionIsOfferedEvenWithNoProjectRegistered() async {
        let secretary = makeSecretary(projects: [])
        secretary.setBrowserEnabled(true)
        provider.denialsForNextTurn = [
            DeniedTool(
                name: BrowserTools.rule(for: "computer"),
                target: .none(),
                rules: [BrowserTools.rule(for: "computer")]
            )
        ]
        secretary.submit("scroll down the page")
        await waitUntilIdle()

        guard case .approval(let request, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected to be asked. Got: \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(request.actionClass, .browserAction)
        XCTAssertFalse(mayBeRemembered(request.actionClass))
    }

    func testTheCardSaysWhatItWillDoRatherThanTheRuleName() async {
        let secretary = makeSecretary(projects: [])
        secretary.setBrowserEnabled(true)
        provider.denialsForNextTurn = [
            DeniedTool(
                name: BrowserTools.rule(for: "computer"),
                target: .none(),
                rules: [BrowserTools.rule(for: "computer")]
            )
        ]
        secretary.submit("scroll down the page")
        await waitUntilIdle()

        guard case .approval(let request, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected to be asked")
        }
        XCTAssertFalse(request.commandSummary.contains("mcp__"), "Got: \(request.commandSummary)")
        XCTAssertTrue(request.commandSummary.contains("click"), "Got: \(request.commandSummary)")

        let said = secretary.transcript.last?.text ?? ""
        XCTAssertTrue(said.contains("your own Chrome"), "Got: \(said)")
        XCTAssertFalse(said.contains("session.Shall"), "Missing gap between sentences: \(said)")
    }

    func testWhileDisconnectedTheModelIsToldToOfferTheChromeExtension() async {
        let secretary = makeSecretary()
        secretary.submit("summarise the page I'm looking at")
        await waitUntilIdle()

        let system = provider.lastSystem ?? ""
        XCTAssertTrue(system.contains("Claude in Chrome"), "Got: \(system)")
        XCTAssertTrue(system.lowercased().contains("sign-in page"), "Got: \(system)")
        XCTAssertTrue(system.contains("Settings"), "Should say where to switch it on. Got: \(system)")
    }

    func testWhileConnectedTheModelIsToldItCanReadTheBrowserAndToDistrustIt() async {
        let secretary = makeSecretary()
        secretary.setBrowserEnabled(true)
        secretary.submit("summarise the page I'm looking at")
        await waitUntilIdle()

        let system = provider.lastSystem ?? ""
        XCTAssertTrue(system.contains("signed in"), "Got: \(system)")
        XCTAssertTrue(system.contains("untrusted"), "Got: \(system)")
        XCTAssertFalse(
            system.contains("switch Browser on in Settings"),
            "Shouldn't offer what is already on. Got: \(system)"
        )
    }
}
