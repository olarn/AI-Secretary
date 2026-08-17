import FunctionalCore
import XCTest
@testable import SecretaryCore

/// Prose that happens to contain a git word is not a git command.
///
/// Found by driving the app on 2026-08-17: the paragraph below was answered
/// with *"No registered project matches …"* and the turn ended there. The model
/// was never called, so from the outside the app had simply gone quiet.
///
/// The chain was `status` (inside "legal status") matching a git rule, then the
/// project split taking everything after the first `" in "` (inside
/// "specializing in") as the project name — some fifty words of it.
final class ProseIsNotACommandTests: XCTestCase {
    private let classifier = RuleBasedIntentClassifier()

    private func isChat(_ text: String) -> Bool {
        if case .unknown = classifier.classify(text) { return true }
        return false
    }

    /// The message that started this, **verbatim**. Not shortened and not
    /// reworded: three properties have to be present at once for it to be the
    /// fixture it is, and rewriting drops one without saying so — the whole
    /// word `status` (in "legal status"), a `" in "` (in "specializing in"),
    /// and several sentence boundaries, which are the only thing that exercises
    /// the single-sentence guard.
    /// One line on purpose. Wrapping it with `\` continuations would rebuild
    /// the paragraph from fragments, and a single misplaced space would be a
    /// fixture that no longer matches what the person typed.
    // swiftlint:disable:next line_length
    private let alphaCapital = "Alpha Capital Group is a company specializing in non-performing asset management through its operating subsidiaries, Alpha Capital Asset Management Co., Ltd. (Alpha) and Wireless Asset Management Co., Ltd. (WAMC). The group manages non-performing loan (NPL) portfolios and non-performing assets (NPA), including property sales, borrower follow-up, collection, legal status, collateral management, customer enquiries, and related service processes"

    func testTheParagraphThatStartedThisIsChat() {
        XCTAssertEqual(classifier.classify(alphaCapital), .unknown(text: alphaCapital))
    }

    /// It has to be caught by *both* guards independently, because each covers
    /// what the other cannot: a paragraph whose last marker happens to be
    /// followed by three short words would pass Guard 1, and a short single
    /// sentence passes Guard 2.
    func testTheParagraphIsCaughtByEachGuardOnItsOwn() {
        XCTAssertFalse(isSingleSentence(alphaCapital), "several sentences")
        XCTAssertEqual(
            splitAtProjectMarker(alphaCapital.lowercased()).project,
            .none(),
            "no tail in it is shaped like a project name"
        )
    }

    func testOtherProseWithGitWordsStaysChat() {
        for text in [
            "The migration log is worth reading. Have a look in the morning.",
            "There were no changes in the pricing. We held steady all quarter.",
            "His branch of the family is the interesting one. Ask him about it.",
            "Do read the history! It goes back a century in this building."
        ] {
            XCTAssertTrue(isChat(text), "Should have stayed chat: \(text)")
        }
    }

    /// **The known residual, pinned rather than papered over.**
    ///
    /// A *single-sentence* statement carrying a git word still classifies as a
    /// command. Guard 1 stops the tail being taken as a project name, but a
    /// query of `.none()` is still a `.codeTool` — only Guard 2 can send a
    /// message to chat, and by construction it cannot fire on one sentence.
    ///
    /// Left as it is on purpose. The remedy is not a smaller word limit: the
    /// Settings-panel lesson is that a tuned number is always exceeded, and any
    /// value low enough to reject "that report is worth reading" also rejects
    /// real names. The actual cure is Sprint 16 — a backend with its own tools
    /// never consults this classifier at all, and prose reaches the model.
    ///
    /// This test exists so that stops being invisible. If Sprint 16 lands and
    /// the fallback classifier is still the only reader, that is the moment to
    /// revisit `handleTool`'s `.notFound` arm.
    func testASingleSentenceStatementStillMisclassifies() {
        let text = "the migration log in that report is worth reading"
        XCTAssertTrue(isSingleSentence(text), "one sentence, so Guard 2 cannot help")
        XCTAssertFalse(isChat(text), "known gap — see this test's comment before changing it")
    }

    // MARK: - The name guard on its own

    func testLooksLikeProjectName() {
        XCTAssertTrue(looksLikeProjectName("AI-Secretary"))
        XCTAssertTrue(looksLikeProjectName("TISCO - AI Sharing"))
        XCTAssertFalse(looksLikeProjectName(""))
        XCTAssertFalse(looksLikeProjectName(alphaCapital))
    }

    func testAProjectNameStopsAtSentencePunctuation() {
        XCTAssertFalse(looksLikeProjectName("Alpha Capital Asset Management Co., Ltd"))
        XCTAssertFalse(looksLikeProjectName("one two three four five six"))
        XCTAssertFalse(looksLikeProjectName(String(repeating: "a", count: 61)))
        XCTAssertTrue(looksLikeProjectName(String(repeating: "a", count: 60)))
    }

    /// The name is at the end of a request, so the *last* qualifying marker
    /// wins. Taking the first one is what let "specializing in …" swallow the
    /// paragraph.
    func testTheLastQualifyingMarkerWins() {
        let split = splitAtProjectMarker("what changed in the parser in AI-Secretary")
        XCTAssertEqual(split.project, .some("AI-Secretary"))
        XCTAssertEqual(split.head, "what changed in the parser")
    }

    func testATailThatIsNotANameIsNoProjectAtAll() {
        XCTAssertEqual(
            splitAtProjectMarker("status in a folder that nobody would ever call this, honestly").project,
            .none()
        )
    }

    /// The case that breaks most quietly: the tail after `" on "` is empty once
    /// the `?` is trimmed, so there is no project — but it is still a command.
    func testWhichBranchAmIOn() {
        XCTAssertEqual(splitAtProjectMarker("which branch am i on?").project, .none())
        XCTAssertTrue(isSingleSentence("which branch am i on?"))
        XCTAssertFalse(isChat("which branch am I on?"))
    }

    // MARK: - The sentence guard on its own

    func testSentenceBoundaries() {
        XCTAssertTrue(isSingleSentence("what's the git status?"))
        XCTAssertTrue(isSingleSentence("read README.md in AI-Secretary"))
        XCTAssertTrue(isSingleSentence("status."), "a boundary at the very end is not internal")
        XCTAssertFalse(isSingleSentence("First this. Then the status."))
        XCTAssertFalse(isSingleSentence("Really? The status, then."))
        XCTAssertFalse(isSingleSentence("Do it! And check the log."))
    }

    /// Real commands are one sentence by construction, so the guard costs them
    /// nothing — this is the half that would show up as the feature breaking.
    func testRealCommandsAreUntouched() {
        for text in [
            "git status in AI-Secretary",
            "show me the log",
            "what's changed in AI-Secretary",
            "which branch am I on?"
        ] {
            XCTAssertFalse(isChat(text), "Should have been a command: \(text)")
        }
    }
}
