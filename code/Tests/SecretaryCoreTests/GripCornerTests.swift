import XCTest
@testable import SecretaryCore

/// Which corner the resize grip belongs in.
///
/// All four combinations are pinned, not just the flipped ones: two of them were
/// already right and the point of the test is that they stay right.
final class GripCornerTests: XCTestCase {
    private func corner(mirrored: Bool, flipped: Bool) -> GripCorner {
        GripCorner.forBubble(isMirrored: mirrored, isFlippedVertically: flipped)
    }

    /// The default placement: bubble above and to the character's right, tail at
    /// the bottom-left, button row top-left, grip top-right.
    func testTheUsualPlacementPutsTheGripTopTrailing() {
        XCTAssertEqual(corner(mirrored: false, flipped: false), GripCorner(isBottom: false, isLeading: false))
    }

    /// Mirrored: the tail moves to the right, so the grip crosses to the left.
    func testMirroringMovesTheGripToTheOtherSide() {
        XCTAssertEqual(corner(mirrored: true, flipped: false), GripCorner(isBottom: false, isLeading: true))
    }

    /// The change. Flipped below the character the top edge is pinned to the
    /// tail and the bubble grows downward, so the grip has to be down there —
    /// left at the top it asked for a drag toward the character, away from the
    /// empty half of the screen being filled.
    func testFlippingBelowTheCharacterMovesTheGripToTheBottom() {
        XCTAssertEqual(corner(mirrored: false, flipped: true), GripCorner(isBottom: true, isLeading: false))
        XCTAssertEqual(corner(mirrored: true, flipped: true), GripCorner(isBottom: true, isLeading: true))
    }

    /// The grip must never share the button row's corner. The row is always on
    /// the tail's side of the top edge.
    func testTheGripNeverSharesTheButtonRowsCorner() {
        for mirrored in [false, true] {
            for flipped in [false, true] {
                let grip = corner(mirrored: mirrored, flipped: flipped)
                let rowIsLeading = !mirrored
                XCTAssertFalse(
                    !grip.isBottom && grip.isLeading == rowIsLeading,
                    "mirrored=\(mirrored) flipped=\(flipped): grip landed on the button row"
                )
            }
        }
    }

    /// The glyph lies along the diagonal of whichever corner it is in, so it
    /// reads as a handle rather than an arbitrary arrow.
    func testTheGlyphPointsAlongItsOwnCornersDiagonal() {
        XCTAssertEqual(corner(mirrored: false, flipped: false).glyphRotation, 90)
        XCTAssertEqual(corner(mirrored: true, flipped: false).glyphRotation, 0)
        XCTAssertEqual(corner(mirrored: false, flipped: true).glyphRotation, 0)
        XCTAssertEqual(corner(mirrored: true, flipped: true).glyphRotation, 90)
    }
}
