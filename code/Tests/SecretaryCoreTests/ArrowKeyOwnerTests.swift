import XCTest
@testable import SecretaryCore

final class ArrowKeyOwnerTests: XCTestCase {
    func testAQuestionOnScreenOwnsTheArrows() {
        XCTAssertEqual(
            ArrowKeyOwner.owner(hasChoices: true, draft: "", hasHistory: true),
            .choiceList,
            "A visible picker must win over recall, or the two fight over one key"
        )
    }

    func testTypingHandsTheArrowsBackToHistory() {
        XCTAssertEqual(
            ArrowKeyOwner.owner(hasChoices: true, draft: "blue, actually", hasHistory: true),
            .history
        )
    }

    func testWithNoQuestionTheArrowsAreHistory() {
        XCTAssertEqual(ArrowKeyOwner.owner(hasChoices: false, draft: "", hasHistory: true), .history)
    }

    func testAMultiLineDraftKeepsTheArrowsForTheCaret() {
        for hasChoices in [true, false] {
            XCTAssertEqual(
                ArrowKeyOwner.owner(hasChoices: hasChoices, draft: "one\ntwo", hasHistory: true),
                .textCaret,
                "hasChoices: \(hasChoices)"
            )
        }
    }

    func testWithNothingToRecallTheFieldKeepsTheKey() {
        XCTAssertEqual(ArrowKeyOwner.owner(hasChoices: false, draft: "", hasHistory: false), .textCaret)
        XCTAssertEqual(ArrowKeyOwner.owner(hasChoices: false, draft: "hi", hasHistory: false), .textCaret)
    }

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
