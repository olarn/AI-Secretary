import XCTest
@testable import SecretaryCore

/// Keywords must match words, not fragments of them.
///
/// Found by driving the app: asking whether a web page was "login" ran `git log`
/// and then failed with "not in the allowlist", because the git rules matched on
/// a bare `contains`. The tool path needs a registered project; ordinary chat
/// does not — so a misfire here doesn't just answer oddly, it refuses work the
/// app was perfectly able to do.
final class KeywordBoundaryTests: XCTestCase {
    private let classifier = RuleBasedIntentClassifier()

    private func isChat(_ text: String) -> Bool {
        if case .unknown = classifier.classify(text) { return true }
        return false
    }

    func testTheWordThatStartedThis() {
        XCTAssertTrue(isChat("is that page login or not?"))
        XCTAssertTrue(isChat("อ่าน tab ที่เปิดอยู่ บอกว่าหน้านั้น login อยู่หรือเปล่า"))
    }

    /// Every git keyword is short enough to hide inside an ordinary word.
    func testKeywordsBuriedInLongerWordsAreNotCommands() {
        for text in [
            "why are these two designs so different?",
            "the logistics are a mess",
            "tell me about statuses in general",
            "what does branching mean in biology?"
        ] {
            XCTAssertTrue(isChat(text), "Should have stayed chat: \(text)")
        }
    }

    /// The rules still have to fire when the word really is there.
    func testRealCommandsStillClassify() {
        for text in ["what's the git status?", "show me the log", "which branch am I on?"] {
            XCTAssertFalse(isChat(text), "Should have been a command: \(text)")
        }
    }

    /// Punctuation and quotes are boundaries, not part of the word.
    func testPunctuationCountsAsABoundary() {
        XCTAssertTrue(RuleBasedIntentClassifier.containsWord("log", in: "show the (log)"))
        XCTAssertTrue(RuleBasedIntentClassifier.containsWord("log", in: "log"))
        XCTAssertFalse(RuleBasedIntentClassifier.containsWord("log", in: "logistics"))
        XCTAssertFalse(RuleBasedIntentClassifier.containsWord("log", in: "backlog2"))
    }

    /// A keyword sitting between Thai characters is still its own word: Thai has
    /// no spaces, so an English term inside a Thai sentence often has none
    /// around it.
    func testAnEnglishKeywordInsideThaiTextStillCounts() {
        XCTAssertTrue(RuleBasedIntentClassifier.containsWord("log", in: "ขอดูlogหน่อย"))
    }

    /// Multi-word keywords go through the same check.
    func testPhrasesAreMatchedAsPhrases() {
        XCTAssertTrue(RuleBasedIntentClassifier.containsWord("changed files", in: "the changed files please"))
        XCTAssertFalse(RuleBasedIntentClassifier.containsWord("changed files", in: "changed filesystem"))
    }

    /// The scan must move past a rejected hit rather than stopping at the first
    /// one or spinning on it.
    func testALaterRealMatchIsFoundAfterAFalseOne() {
        XCTAssertTrue(RuleBasedIntentClassifier.containsWord("log", in: "logistics aside, show the log"))
    }
}
