import XCTest
@testable import SecretaryCore

final class CharacterLaunchOriginTests: XCTestCase {
    private let character = CGSize(width: 150, height: 200)

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

    func testMayStandOverTheDock() {
        let visible = CGRect(x: 0, y: 90, width: 1920, height: 1350)
        let origin = CharacterLaunch.origin(
            characterSize: character,
            visibleFrame: visible,
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1440)
        )
        XCTAssertEqual(origin.y, 90 + 120 - 135, accuracy: 0.001)
        XCTAssertLessThan(origin.y, visible.minY)
    }

    func testNeverBelowTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
        let origin = CharacterLaunch.origin(
            characterSize: character,
            visibleFrame: visible,
            screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertGreaterThanOrEqual(origin.y, 0)
    }

    func testATallCharacterIsPinnedToTheBottom() {
        let origin = CharacterLaunch.origin(
            characterSize: CGSize(width: 400, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertEqual(origin.y, 0)
    }

    func testLoweredByATenthOfTheUsableHeightOnEveryScreen() {
        for height in [800.0, 1030.0, 1440.0] {
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
