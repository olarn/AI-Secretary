import XCTest
@testable import SecretaryCore

/// Where the character stands on first launch.
final class CharacterLaunchOriginTests: XCTestCase {
    private let character = CGSize(width: 150, height: 200)

    /// The owner's display: 1728×1117 with a Dock, so 1030pt of usable height.
    /// The old resting position was 120pt up from the Dock; a tenth of the
    /// usable height comes off that.
    func testStandsLowerThanTheOldRestingHeight() {
        let visible = CGRect(x: 0, y: 54, width: 1728, height: 1030)
        let origin = CharacterLaunch.origin(
            characterSize: character,
            visibleFrame: visible,
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
        )
        XCTAssertEqual(origin.y, 54 + 120 - 103, accuracy: 0.001)
        XCTAssertLessThan(origin.y, 54 + CharacterLaunch.restingHeight)
    }

    func testKeepsTheSameDistanceInFromTheRightEdge() {
        let visible = CGRect(x: 0, y: 54, width: 1728, height: 1030)
        let origin = CharacterLaunch.origin(
            characterSize: character,
            visibleFrame: visible,
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
        )
        XCTAssertEqual(origin.x, 1728 - CharacterLaunch.insetFromRight)
    }

    /// Onto the Dock is allowed — the clamp is the whole screen, the same
    /// rectangle `keepCharacterOnScreen` uses. Launching against the visible
    /// frame instead would put the character somewhere a resize is then free to
    /// move it away from.
    func testMayStandOverTheDock() {
        // Tall enough that a tenth of it is more than the 120pt the character
        // used to stand up — so the new position is inside the Dock's strip.
        let visible = CGRect(x: 0, y: 90, width: 1920, height: 1350)
        let origin = CharacterLaunch.origin(
            characterSize: character,
            visibleFrame: visible,
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1440)
        )
        XCTAssertEqual(origin.y, 90 + 120 - 135, accuracy: 0.001)
        XCTAssertLessThan(origin.y, visible.minY)
    }

    /// Never off the bottom, however short the screen.
    func testNeverBelowTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
        let origin = CharacterLaunch.origin(
            characterSize: character,
            visibleFrame: visible,
            screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertGreaterThanOrEqual(origin.y, 0)
    }

    /// A character taller than the screen is pinned to the bottom rather than
    /// to a negative position, which is what a naive clamp would produce.
    func testATallCharacterIsPinnedToTheBottom() {
        let origin = CharacterLaunch.origin(
            characterSize: CGSize(width: 400, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertEqual(origin.y, 0)
    }

    /// The whole point of the change, stated once: on any screen it now stands
    /// a tenth of the usable height lower than it used to.
    func testLoweredByATenthOfTheUsableHeightOnEveryScreen() {
        for height in [800.0, 1030.0, 1440.0] {
            // A Dock below the usable area, as on a real screen — otherwise the
            // tallest case is lowered onto the bottom of the display and the
            // clamp, not the rule, is what decides where it lands.
            let visible = CGRect(x: 0, y: 150, width: 1600, height: height)
            let origin = CharacterLaunch.origin(
                characterSize: character,
                visibleFrame: visible,
                screenFrame: CGRect(x: 0, y: 0, width: 1600, height: height + 200)
            )
            let old = visible.minY + CharacterLaunch.restingHeight
            XCTAssertEqual(old - origin.y, height * 0.10, accuracy: 0.001, "height=\(height)")
        }
    }
}
