import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

final class WebTaskDetectionTests: XCTestCase {

    func testAPlainLinkIsFound() {
        XCTAssertEqual(
            webAddress(in: "have a look at https://example.com/board/7").toOptional()?.absoluteString,
            "https://example.com/board/7"
        )
    }

    func testTrailingPunctuationBelongsToTheSentence() {
        XCTAssertEqual(
            webAddress(in: "it's at https://example.com/board, the second tab").toOptional()?.absoluteString,
            "https://example.com/board"
        )
        XCTAssertEqual(
            webAddress(in: "(see https://example.com/x)").toOptional()?.absoluteString,
            "https://example.com/x"
        )
    }

    func testAWwwAddressCountsBecauseThatIsHowPeopleWriteThem() {
        XCTAssertEqual(
            webAddress(in: "www.example.com please").toOptional()?.absoluteString,
            "https://www.example.com"
        )
    }

    func testAnOrdinarySentenceIsNotAnAddress() {
        for text in ["open config.json", "it's about node.js", "bump to v2.1", "example.com"] {
            XCTAssertEqual(webAddress(in: text), Option.none(), "Got a link out of: \(text)")
        }
    }

    func testOnlyHttpAndHttpsCount() {
        XCTAssertEqual(webAddress(in: "file:///etc/passwd"), Option.none())
        XCTAssertEqual(webAddress(in: "slack://channel?id=1"), Option.none())
        XCTAssertEqual(
            webAddress(in: "http://localhost:8080/admin").toOptional()?.absoluteString,
            "http://localhost:8080/admin"
        )
    }

    func testTheFirstLinkWins() {
        XCTAssertEqual(
            webAddress(in: "compare https://a.example.com and https://b.example.com")
                .toOptional()?.host(),
            "a.example.com"
        )
    }

    func testTheGrantIsScopedToTheSiteNotThePage() {
        let url = URL(string: "https://WWW.Example.com/board/7?x=1")!
        XCTAssertEqual(webSiteHost(of: url), Option.some("example.com"))
    }

    func testGrantsAreCaseInsensitiveBothWays() {
        let grants = WebSiteGrants().granting(host: "Example.COM")
        XCTAssertTrue(grants.allows(host: "example.com"))
        XCTAssertTrue(grants.allows(host: "EXAMPLE.com"))
        XCTAssertFalse(grants.allows(host: "other.example.com"))
    }

    func testASubdomainIsNotTheSameSite() {
        let grants = WebSiteGrants().granting(host: "example.com")
        XCTAssertFalse(grants.allows(host: "admin.example.com"))
    }

    func testNothingIsSaidToTheModelUntilASiteIsApproved() {
        XCTAssertEqual(webSiteNote(hosts: []), "")
        XCTAssertTrue(webSiteNote(hosts: ["example.com"]).contains("example.com"))
    }
}

@MainActor
final class WebTaskFlowTests: XCTestCase {
    private let machine = AssistantStateMachine()

    private func makeSecretary(_ provider: SpyWorkspaceProvider) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            activityPreference: InMemoryActivityPreference(),
            browserPreference: InMemoryBrowserPreference(),
            chatProvider: provider
        )
    }

    private func settle() async {
        let deadline = Date().addingTimeInterval(2)
        while machine.state.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testALinkStopsTheTurnAndAsksFirst() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider)

        secretary.submit("fill in the form at https://example.com/new")
        await settle()

        guard case .website(let request)? = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected the site card, got \(String(describing: secretary.pendingDecision.toOptional()))")
        }
        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(provider.callCount, 0, "Nothing may reach the model before the card is answered")
    }

    func testApprovingRunsTheMessageThatRaisedItWithoutRetyping() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider)
        secretary.submit("fill in the form at https://example.com/new")

        secretary.resolveWebTask(granted: true)
        await settle()

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(provider.lastMessages.last?.content, "fill in the form at https://example.com/new")
        XCTAssertEqual(secretary.pendingDecision, Option.none())
    }

    func testEitherAnswerToTheSiteCardIsWrittenDown() async {
        let yes = SpyWorkspaceProvider()
        let approving = makeSecretary(yes)
        approving.submit("fill in the form at https://example.com/new")
        approving.resolveWebTask(granted: true)
        await settle()
        XCTAssertTrue(approving.transcript.contains { $0.text.contains(chosenLine(CardChoice.goAhead)) })

        let no = SpyWorkspaceProvider()
        let refusing = makeSecretary(no)
        refusing.submit("fill in the form at https://example.com/new")
        refusing.resolveWebTask(granted: false)
        await settle()
        XCTAssertTrue(refusing.transcript.contains { $0.text.contains(chosenLine(CardChoice.notThisOne)) })
    }

    func testDenyingOpensNothing() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider)
        secretary.submit("fill in the form at https://example.com/new")

        secretary.resolveWebTask(granted: false)
        await settle()

        XCTAssertEqual(provider.callCount, 0)
        XCTAssertTrue(
            secretary.transcript.contains { $0.text.contains("haven't opened example.com") },
            "Refusing has to be said, not merely not-done"
        )
    }

    func testTheSameSiteIsNotAskedAboutTwice() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider)
        secretary.submit("start at https://example.com/new")
        secretary.resolveWebTask(granted: true)
        await settle()

        secretary.submit("now https://example.com/other")
        await settle()

        XCTAssertEqual(secretary.pendingDecision, Option.none())
        XCTAssertEqual(provider.callCount, 2)
    }

    func testADifferentSiteIsAskedAboutAgain() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider)
        secretary.submit("start at https://example.com/new")
        secretary.resolveWebTask(granted: true)
        await settle()

        secretary.submit("and https://elsewhere.test/thing")
        await settle()

        guard case .website(let request)? = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected a second card for a second site")
        }
        XCTAssertEqual(request.host, "elsewhere.test")
    }

    func testApprovingConnectsTheBrowserWhenItWasOff() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider)
        XCTAssertFalse(secretary.browserEnabled)

        secretary.submit("https://example.com/new")
        guard case .website(let request)? = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected the site card")
        }
        XCTAssertTrue(request.connectsBrowser)
        XCTAssertTrue(request.summary.contains("Connect Chrome"))

        secretary.resolveWebTask(granted: true)
        await settle()

        XCTAssertTrue(secretary.browserEnabled)
        XCTAssertEqual(provider.browserEnabledCalls.last, true)
    }

    func testApprovingAlsoAllowsOpeningThePage() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider)
        secretary.submit("https://example.com/new")
        secretary.resolveWebTask(granted: true)
        await settle()

        XCTAssertTrue(
            provider.preparedTools.compactMap { $0 }.last?
                .contains(BrowserTools.rule(for: "navigate")) == true,
            "Got: \(String(describing: provider.preparedTools.last))"
        )
    }

    func testTheModelIsToldWhichSiteItMayWorkIn() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider)
        secretary.submit("https://example.com/new")
        secretary.resolveWebTask(granted: true)
        await settle()

        let system = provider.lastSystem ?? ""
        XCTAssertTrue(system.contains("example.com"), "The prompt must name the approved site")
        XCTAssertTrue(system.contains("untrusted"), "…and that the page can't be trusted")
    }

    func testANewConversationForgetsTheSite() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider)
        secretary.submit("https://example.com/new")
        secretary.resolveWebTask(granted: true)
        await settle()

        secretary.newConversation()
        secretary.submit("https://example.com/other")
        await settle()

        guard case .website? = secretary.pendingDecision.toOptional() else {
            return XCTFail("A new conversation must ask about the site again")
        }
    }

    func testMovingOnWithoutAnsweringSaysSo() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider)
        secretary.submit("https://example.com/new")

        secretary.submit("never mind")
        await settle()

        XCTAssertTrue(secretary.transcript.contains { $0.text.hasPrefix("(Didn't do") })
        XCTAssertEqual(secretary.pendingDecision, Option.none())
    }
}
