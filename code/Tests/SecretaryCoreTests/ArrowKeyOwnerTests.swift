import XCTest
@testable import SecretaryCore

/// Up and Down are wanted by three features at once. These pin down which one
/// gets them, so the answer can't drift back to "whichever `if` came first".
///
/// Note what this can and can't prove: it fixes the rule, not the plumbing.
/// Whether the key reaches the rule at all is a question only the running app
/// answers — `.onKeyPress` never saw an arrow here, and the code read fine.
final class ArrowKeyOwnerTests: XCTestCase {
    func testAQuestionOnScreenOwnsTheArrows() {
        XCTAssertEqual(
            ArrowKeyOwner.owner(hasChoices: true, draft: "", hasHistory: true),
            .choiceList,
            "A visible picker must win over recall, or the two fight over one key"
        )
    }

    /// Typing is how you say "I'll answer in my own words" — at which point the
    /// arrows go back to being history, exactly as Return already behaved.
    func testTypingHandsTheArrowsBackToHistory() {
        XCTAssertEqual(
            ArrowKeyOwner.owner(hasChoices: true, draft: "blue, actually", hasHistory: true),
            .history
        )
    }

    func testWithNoQuestionTheArrowsAreHistory() {
        XCTAssertEqual(ArrowKeyOwner.owner(hasChoices: false, draft: "", hasHistory: true), .history)
    }

    /// In a draft spanning lines the arrows are the only way between them, so
    /// nothing may take them — not the picker's business either, since a
    /// multi-line draft is never empty.
    func testAMultiLineDraftKeepsTheArrowsForTheCaret() {
        for hasChoices in [true, false] {
            XCTAssertEqual(
                ArrowKeyOwner.owner(hasChoices: hasChoices, draft: "one\ntwo", hasHistory: true),
                .textCaret,
                "hasChoices: \(hasChoices)"
            )
        }
    }

    /// Nothing to recall and nothing to choose: the field keeps its own keys
    /// rather than swallowing them to do nothing.
    func testWithNothingToRecallTheFieldKeepsTheKey() {
        XCTAssertEqual(ArrowKeyOwner.owner(hasChoices: false, draft: "", hasHistory: false), .textCaret)
        XCTAssertEqual(ArrowKeyOwner.owner(hasChoices: false, draft: "hi", hasHistory: false), .textCaret)
    }

    /// Exactly one owner for every combination of the three inputs — the
    /// property that makes "they clash" unrepresentable rather than unlikely.
    func testEveryStateHasExactlyOneOwner() {
        for hasChoices in [true, false] {
            for draft in ["", "one line", "one\ntwo"] {
                for hasHistory in [true, false] {
                    let owner = ArrowKeyOwner.owner(
                        hasChoices: hasChoices, draft: draft, hasHistory: hasHistory
                    )
                    switch owner {
                    case .choiceList:
                        XCTAssertTrue(hasChoices, "Picked the list with no options")
                        XCTAssertTrue(draft.isEmpty, "Picked the list mid-draft: \(draft)")
                    case .history:
                        XCTAssertTrue(hasHistory, "Chose recall with nothing to recall")
                        XCTAssertFalse(draft.contains("\n"), "Chose recall in a multi-line draft")
                    case .textCaret:
                        break
                    }
                }
            }
        }
    }
}
