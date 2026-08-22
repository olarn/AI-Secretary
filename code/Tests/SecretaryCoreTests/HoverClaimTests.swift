import XCTest
@testable import SecretaryCore

final class HoverClaimTests: XCTestCase {
    func testEnteringABoxClaimsIt() {
        XCTAssertEqual(hoverClaim(current: nil, box: 3, pointerIsInside: true), 3)
    }

    func testEnteringWhileAnotherBoxHoldsItTakesItOver() {
        XCTAssertEqual(hoverClaim(current: 1, box: 3, pointerIsInside: true), 3)
    }

    func testLeavingTheBoxThatHoldsItPutsTheButtonsAway() {
        XCTAssertNil(hoverClaim(current: 3, box: 3, pointerIsInside: false))
    }

    func testLeavingABoxThatNoLongerHoldsItChangesNothing() {
        XCTAssertEqual(hoverClaim(current: 4, box: 3, pointerIsInside: false), 4)
    }

    func testLeavingWhenNobodyHoldsItIsStillNobody() {
        XCTAssertNil(hoverClaim(current: nil, box: 3, pointerIsInside: false))
    }

    func testASweepAcrossBoxesNeverFlickersToNothing() {
        var claim: Int?
        for box in 1...5 {
            claim = hoverClaim(current: claim, box: box, pointerIsInside: true)
            XCTAssertEqual(claim, box)
            claim = hoverClaim(current: claim, box: box - 1, pointerIsInside: false)
            XCTAssertEqual(claim, box, "the leave of the box behind took the claim with it")
        }
    }
}
