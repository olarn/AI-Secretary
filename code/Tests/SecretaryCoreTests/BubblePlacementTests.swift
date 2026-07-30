import CoreGraphics
import XCTest
@testable import SecretaryCore

/// Where the speech bubble lands.
///
/// The case that matters is a bubble too tall for the space above the
/// character. Flipping it below looks like the obvious answer and is wrong when
/// there is even less room down there: the flipped origin gets clamped back
/// onto the screen and the bubble ends up covering the character.
final class BubblePlacementTests: XCTestCase {
    /// A 1920×1080 display with the menu bar and Dock taken out, matching the
    /// screen these were measured on.
    private let screen = CGRect(x: 0, y: 54, width: 1920, height: 996)

    private func place(
        character: CGRect,
        bubble: CGSize
    ) -> BubblePlacement {
        placeBubble(
            character: character,
            bubble: bubble,
            visibleFrame: screen,
            tailTipOffset: 44,
            clearance: character.width * 0.28,
            gap: -14,
            margin: 8
        )
    }

    /// The character standing at the bottom of the screen, over the Dock,
    /// where the app puts it by default.
    private let standing = CGRect(x: 1744, y: 30, width: 128, height: 149)

    func testTheBubbleSitsAboveTheCharacterWhenItFits() {
        let placement = place(character: standing, bubble: CGSize(width: 484, height: 500))
        XCTAssertFalse(placement.isFlippedVertically)
        XCTAssertEqual(placement.origin.y, 165, accuracy: 0.5)
    }

    /// The reported bug, at the size it was measured: 883pt of bubble over a
    /// character standing on the Dock flipped below and swallowed it whole.
    func testATallBubbleDoesNotFlipOntoACharacterStandingLow() {
        let bubble = CGSize(width: 484, height: 883)
        let placement = place(character: standing, bubble: bubble)

        XCTAssertFalse(
            placement.isFlippedVertically,
            "There is less room below a character on the Dock than above it"
        )
        let frame = CGRect(origin: placement.origin, size: bubble)
        XCTAssertLessThan(
            frame.minY, screen.maxY,
            "Sanity: the bubble is on screen"
        )
        XCTAssertGreaterThan(
            frame.minY, standing.minY,
            "The bubble must not reach down past the character's feet"
        )
    }

    /// The flip still has to work — it is why the code exists. A character up
    /// near the menu bar has no room above it and plenty below.
    func testTheBubbleFlipsBelowACharacterNearTheTop() {
        let high = CGRect(x: 1744, y: 880, width: 128, height: 149)
        let bubble = CGSize(width: 484, height: 500)
        let placement = place(character: high, bubble: bubble)

        XCTAssertTrue(placement.isFlippedVertically)
        XCTAssertEqual(placement.origin.y, 880 - 500 + 14, accuracy: 0.5)
    }

    /// Neither side fits: take the roomier one rather than always flipping.
    func testWithNoRoomEitherSideTheRoomierSideWins() {
        let bubble = CGSize(width: 484, height: 940)
        XCTAssertTrue(
            place(
                character: CGRect(x: 1744, y: 800, width: 128, height: 149),
                bubble: bubble
            ).isFlippedVertically,
            "Character high on screen: below is the roomier side"
        )
        XCTAssertFalse(
            place(character: standing, bubble: bubble).isFlippedVertically,
            "Character on the Dock: above is the roomier side"
        )
    }

    /// Whatever it decides, the bubble stays on screen.
    func testTheBubbleIsAlwaysOnScreen() {
        for y in stride(from: CGFloat(30), through: 950, by: 40) {
            for height in [CGFloat(320), 640, 883, 980] {
                let placement = place(
                    character: CGRect(x: 1744, y: y, width: 128, height: 149),
                    bubble: CGSize(width: 484, height: height)
                )
                XCTAssertGreaterThanOrEqual(
                    placement.origin.y, screen.minY,
                    "y=\(y) height=\(height)"
                )
                XCTAssertLessThanOrEqual(
                    placement.origin.y + height, screen.maxY,
                    "y=\(y) height=\(height)"
                )
            }
        }
    }

    /// Horizontal behaviour is unchanged: the tail mirrors near the right edge
    /// and the bubble grows leftward instead of off the screen.
    func testTheBubbleMirrorsNearTheRightEdge() {
        let placement = place(character: standing, bubble: CGSize(width: 484, height: 400))
        XCTAssertTrue(placement.isMirrored)
        XCTAssertLessThanOrEqual(placement.origin.x + 484, screen.maxX - 8)
    }

    func testTheBubbleDoesNotMirrorWithRoomToItsRight() {
        let placement = place(
            character: CGRect(x: 200, y: 30, width: 128, height: 149),
            bubble: CGSize(width: 484, height: 400)
        )
        XCTAssertFalse(placement.isMirrored)
    }
}
