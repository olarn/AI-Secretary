import XCTest
@testable import SecretaryCore

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

    func testRealCommandsStillClassify() {
        for text in ["what's the git status?", "show me the log", "which branch am I on?"] {
            XCTAssertFalse(isChat(text), "Should have been a command: \(text)")
        }
    }

    func testPunctuationCountsAsABoundary() {
        XCTAssertTrue(RuleBasedIntentClassifier.containsWord("log", in: "show the (log)"))
        XCTAssertTrue(RuleBasedIntentClassifier.containsWord("log", in: "log"))
        XCTAssertFalse(RuleBasedIntentClassifier.containsWord("log", in: "logistics"))
        XCTAssertFalse(RuleBasedIntentClassifier.containsWord("log", in: "backlog2"))
    }

    func testAnEnglishKeywordInsideThaiTextStillCounts() {
        XCTAssertTrue(RuleBasedIntentClassifier.containsWord("log", in: "ขอดูlogหน่อย"))
    }

    func testPhrasesAreMatchedAsPhrases() {
        XCTAssertTrue(RuleBasedIntentClassifier.containsWord("changed files", in: "the changed files please"))
        XCTAssertFalse(RuleBasedIntentClassifier.containsWord("changed files", in: "changed filesystem"))
    }

    func testALaterRealMatchIsFoundAfterAFalseOne() {
        XCTAssertTrue(RuleBasedIntentClassifier.containsWord("log", in: "logistics aside, show the log"))
    }
}
