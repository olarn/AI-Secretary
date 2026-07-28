import FunctionalCore
import XCTest
import AssistantState
import ProjectRegistry
import ToolAdapters
import LLMProvider
@testable import SecretaryCore

/// Reading web pages through the user's own browser: what it takes to turn on,
/// what it lets the assistant do unasked, and what it is told to say when it is
/// off.
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
            classifier: RuleBasedIntentClassifier(),
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

    /// The tools handed to the backend on the last turn.
    private func lastAllowedTools() -> [String] {
        provider.preparedTools.compactMap { $0 }.last ?? []
    }

    // MARK: - Turning it on

    func testTheBrowserStartsDisconnected() {
        XCTAssertFalse(makeSecretary().browserEnabled)
    }

    /// A permission that survives quitting has to survive relaunching, so the
    /// backend is told at startup rather than only when the switch is flipped.
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

    /// The change decides what the assistant can answer, so it is announced
    /// where the answers are — and it says whose session is being used, since
    /// that is the part a person would reasonably worry about.
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

    // MARK: - What may run without asking

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

    /// Clicking and typing inside a signed-in browser never ride along with
    /// permission to read. They take the same refuse-then-ask path as every
    /// other action with a side effect.
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

    /// Ordinary file and git access must not be lost when the browser joins.
    func testConnectingTheBrowserKeepsTheExistingTools() async {
        let secretary = makeSecretary()
        secretary.setBrowserEnabled(true)
        secretary.submit("hello")
        await waitUntilIdle()
        XCTAssertTrue(lastAllowedTools().contains("Read"))
        XCTAssertTrue(lastAllowedTools().contains("Grep"))
    }

    // MARK: - Being asked for the browser

    /// The offer to allow is the only way permissions widen here, and it used
    /// to require a registered project. Browser work belongs to no project and
    /// often runs with none registered at all, so the offer never appeared and
    /// the action stayed permanently out of reach.
    func testABlockedBrowserActionIsOfferedEvenWithNoProjectRegistered() async {
        let secretary = makeSecretary(projects: [])
        secretary.setBrowserEnabled(true)
        provider.denialsForNextTurn = [
            DeniedTool(
                name: BrowserTools.rule(for: "computer"),
                target: .none(),
                rule: BrowserTools.rule(for: "computer")
            )
        ]
        secretary.submit("scroll down the page")
        await waitUntilIdle()

        guard case .approval(let request, _) = secretary.pendingDecision else {
            return XCTFail("Expected to be asked. Got: \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(request.actionClass, .browserAction)
        XCTAssertFalse(request.actionClass.canRunUnattended)
    }

    /// Nobody can weigh `mcp__claude-in-chrome__computer`. The card has to say
    /// what will happen — including the parts they didn't ask for, since one
    /// rule covers scrolling, clicking and typing together.
    func testTheCardSaysWhatItWillDoRatherThanTheRuleName() async {
        let secretary = makeSecretary(projects: [])
        secretary.setBrowserEnabled(true)
        provider.denialsForNextTurn = [
            DeniedTool(
                name: BrowserTools.rule(for: "computer"),
                target: .none(),
                rule: BrowserTools.rule(for: "computer")
            )
        ]
        secretary.submit("scroll down the page")
        await waitUntilIdle()

        guard case .approval(let request, _) = secretary.pendingDecision else {
            return XCTFail("Expected to be asked")
        }
        XCTAssertFalse(request.commandSummary.contains("mcp__"), "Got: \(request.commandSummary)")
        XCTAssertTrue(request.commandSummary.contains("click"), "Got: \(request.commandSummary)")

        // And the chat message has to say whose browser it is.
        let said = secretary.transcript.last?.text ?? ""
        XCTAssertTrue(said.contains("your own Chrome"), "Got: \(said)")
        XCTAssertFalse(said.contains("session.Shall"), "Missing gap between sentences: \(said)")
    }

    // MARK: - What the model is told

    /// The failure this exists to prevent: a fetch of a login-walled page
    /// succeeds and returns the sign-in form, and the model reports that as the
    /// page's content. It has to know the difference, and know what to offer.
    func testWhileDisconnectedTheModelIsToldToOfferTheChromeExtension() async {
        let secretary = makeSecretary()
        secretary.submit("summarise the page I'm looking at")
        await waitUntilIdle()

        let system = provider.lastSystem ?? ""
        XCTAssertTrue(system.contains("Claude in Chrome"), "Got: \(system)")
        XCTAssertTrue(system.lowercased().contains("sign-in page"), "Got: \(system)")
        XCTAssertTrue(system.contains("Settings"), "Should say where to switch it on. Got: \(system)")
    }

    /// And once it is on, the model must know it — and be told that page text
    /// is something to report, not instructions to obey.
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
