import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

/// Recognising a link, and what happens when one arrives.
///
/// The risk this guards is asymmetric. Missing a link costs a card that never
/// appeared; seeing one that isn't there costs a card in front of an ordinary
/// sentence, every time someone mentions a filename. So the detector is
/// deliberately narrow, and these tests hold it there.
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

    /// The reason the detector is not clever. "config.json", "node.js" and
    /// "v2.1" all look like hosts to anything that accepts a bare domain, and
    /// each one would raise a permission card in the middle of a conversation
    /// about files.
    func testAnOrdinarySentenceIsNotAnAddress() {
        for text in ["open config.json", "it's about node.js", "bump to v2.1", "example.com"] {
            XCTAssertEqual(webAddress(in: text), Option.none(), "Got a link out of: \(text)")
        }
    }

    /// `file:` would reach the person's own disk and a custom scheme hands the
    /// address to whatever app claims it — neither is a web app to work in.
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

    // MARK: - The site a grant covers

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

    /// A subdomain is a different site. Approving a public help page must not
    /// carry over to the admin console next door.
    func testASubdomainIsNotTheSameSite() {
        let grants = WebSiteGrants().granting(host: "example.com")
        XCTAssertFalse(grants.allows(host: "admin.example.com"))
    }

    func testNothingIsSaidToTheModelUntilASiteIsApproved() {
        XCTAssertEqual(webSiteNote(hosts: []), "")
        XCTAssertTrue(webSiteNote(hosts: ["example.com"]).contains("example.com"))
    }
}

/// The card, through the Secretary.
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

    /// The second link to a site already agreed to goes straight through. Asked
    /// again per page, the card becomes something to dismiss rather than read.
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

    /// Working in a page as the person needs their session, which means Chrome.
    /// Approving the card connects it — and the card says so, because two
    /// things are being agreed to at once.
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

    /// Opening the page is the first thing the approval is for. Without the
    /// tool being granted here, answering this card leads straight into the
    /// refuse-then-widen card for `navigate` — the same question, asked worse.
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

    /// The grant is session-shaped. A new conversation asks again, or "for this
    /// conversation" on the card is a lie.
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

    /// Typing instead of answering drops the card, and the drop is said out
    /// loud — the model is told too, so the next reply can't claim it went.
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
