import XCTest
@testable import SecretaryCore

final class WindowGeometryTests: XCTestCase {

    func testAShortTableGetsTheMinimumNotAScreenHeightWindow() {
        XCTAssertEqual(infoWindowSize(fitting: CGSize(width: 100, height: 40)),
                       CGSize(width: 320, height: 180))
    }

    func testALongOneIsCappedInsteadOfTryingToFit() {
        XCTAssertEqual(infoWindowSize(fitting: CGSize(width: 2000, height: 3000)),
                       CGSize(width: 720, height: 640))
    }

    func testInBetweenContentGetsItsFittingSizePlusBreathingRoom() {
        XCTAssertEqual(infoWindowSize(fitting: CGSize(width: 400, height: 300)),
                       CGSize(width: 432, height: 332))
    }

    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 950)

    func testEachWindowStepsDownAndRightFromTheLast() {
        let first = infoWindowOrigin(visibleFrame: screen, existingWindows: 0)
        let second = infoWindowOrigin(visibleFrame: screen, existingWindows: 1)
        XCTAssertEqual(first, CGPoint(x: 120, y: 870))
        XCTAssertEqual(second, CGPoint(x: 146, y: 844))
    }

    func testTheCascadeWrapsAfterEight() {
        XCTAssertEqual(infoWindowOrigin(visibleFrame: screen, existingWindows: 8),
                       infoWindowOrigin(visibleFrame: screen, existingWindows: 0))
    }

    func testTheBoxNeverShrinksBelowOneLineNorGrowsPastTheLimit() {
        XCTAssertEqual(messageBoxHeight(draft: 0, lineHeight: 20, lineLimit: 6), 20)
        XCTAssertEqual(messageBoxHeight(draft: 65, lineHeight: 20, lineLimit: 6), 65)
        XCTAssertEqual(messageBoxHeight(draft: 500, lineHeight: 20, lineLimit: 6), 120)
    }

    private func drag(mirrored: Bool = false, flipped: Bool = false) -> ChatResizeDrag {
        ChatResizeDrag(
            pointer: CGPoint(x: 100, y: 100),
            width: 480, height: 600,
            isMirrored: mirrored, isFlippedVertically: flipped
        )
    }

    func testDraggingRightAndUpGrowsTheUsualBubble() {
        XCTAssertEqual(drag().size(at: CGPoint(x: 130, y: 150)),
                       CGSize(width: 510, height: 650))
    }

    func testAMirroredBubbleGrowsLeftward() {
        XCTAssertEqual(drag(mirrored: true).size(at: CGPoint(x: 70, y: 100)),
                       CGSize(width: 510, height: 600))
    }

    func testAFlippedBubbleGrowsDownward() {
        XCTAssertEqual(drag(flipped: true).size(at: CGPoint(x: 100, y: 60)),
                       CGSize(width: 480, height: 640))
    }

    func testTheDirectionsAreFixedForTheWholeDrag() {
        let start = drag(flipped: false)
        let before = start.size(at: CGPoint(x: 100, y: 160))
        let after = start.size(at: CGPoint(x: 100, y: 160))
        XCTAssertEqual(before, after)
        XCTAssertEqual(before.height, 660)
    }

    func testCaptionFontStaysTwoBelowSecondaryWithAFloor() {
        let settings = AppearanceSettings()
        XCTAssertEqual(settings.captionFontSize, max(9, settings.secondaryFontSize - 2))
        let smallest = AppearanceSettings(fontSize: AppearanceSettings.minFontSize)
        XCTAssertEqual(smallest.captionFontSize, 9)
    }
}
