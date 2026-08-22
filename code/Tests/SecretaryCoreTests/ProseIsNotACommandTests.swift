import FunctionalCore
import XCTest
@testable import SecretaryCore

final class ProseIsNotACommandTests: XCTestCase {
    private let classifier = RuleBasedIntentClassifier()

    private func isChat(_ text: String) -> Bool {
        if case .unknown = classifier.classify(text) { return true }
        return false
    }

    private let alphaCapital = "Alpha Capital Group is a company specializing in non-performing asset management through its operating subsidiaries, Alpha Capital Asset Management Co., Ltd. (Alpha) and Wireless Asset Management Co., Ltd. (WAMC). The group manages non-performing loan (NPL) portfolios and non-performing assets (NPA), including property sales, borrower follow-up, collection, legal status, collateral management, customer enquiries, and related service processes"

    func testTheParagraphThatStartedThisIsChat() {
        XCTAssertEqual(classifier.classify(alphaCapital), .unknown(text: alphaCapital))
    }

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

    func testASingleSentenceStatementStillMisclassifies() {
        let text = "the migration log in that report is worth reading"
        XCTAssertTrue(isSingleSentence(text), "one sentence, so Guard 2 cannot help")
        XCTAssertFalse(isChat(text), "known gap — see this test's comment before changing it")
    }

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

    func testWhichBranchAmIOn() {
        XCTAssertEqual(splitAtProjectMarker("which branch am i on?").project, .none())
        XCTAssertTrue(isSingleSentence("which branch am i on?"))
        XCTAssertFalse(isChat("which branch am I on?"))
    }

    func testSentenceBoundaries() {
        XCTAssertTrue(isSingleSentence("what's the git status?"))
        XCTAssertTrue(isSingleSentence("read README.md in AI-Secretary"))
        XCTAssertTrue(isSingleSentence("status."), "a boundary at the very end is not internal")
        XCTAssertFalse(isSingleSentence("First this. Then the status."))
        XCTAssertFalse(isSingleSentence("Really? The status, then."))
        XCTAssertFalse(isSingleSentence("Do it! And check the log."))
    }

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
