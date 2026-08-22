import AppKit
import XCTest
@testable import SecretaryCore

final class GripCornerTests: XCTestCase {
    private func corner(mirrored: Bool, flipped: Bool) -> GripCorner {
        GripCorner.forBubble(isMirrored: mirrored, isFlippedVertically: flipped)
    }

    func testTheUsualPlacementPutsTheGripTopTrailing() {
        XCTAssertEqual(corner(mirrored: false, flipped: false), GripCorner(isBottom: false, isLeading: false))
    }

    func testMirroringMovesTheGripToTheOtherSide() {
        XCTAssertEqual(corner(mirrored: true, flipped: false), GripCorner(isBottom: false, isLeading: true))
    }

    func testFlippingBelowTheCharacterMovesTheGripToTheBottom() {
        XCTAssertEqual(corner(mirrored: false, flipped: true), GripCorner(isBottom: true, isLeading: false))
        XCTAssertEqual(corner(mirrored: true, flipped: true), GripCorner(isBottom: true, isLeading: true))
    }

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

    func testTheGlyphFlipsWithTheCorner() {
        let mainDiagonal = "arrow.up.left.and.arrow.down.right"
        let antiDiagonal = "arrow.down.left.and.arrow.up.right"

        XCTAssertEqual(corner(mirrored: false, flipped: false).glyphName, antiDiagonal, "top-trailing")
        XCTAssertEqual(corner(mirrored: true, flipped: false).glyphName, mainDiagonal, "top-leading")
        XCTAssertEqual(corner(mirrored: false, flipped: true).glyphName, mainDiagonal, "bottom-trailing")
        XCTAssertEqual(corner(mirrored: true, flipped: true).glyphName, antiDiagonal, "bottom-leading")
    }

    func testTheGlyphIsTheOutwardArrowNotTheCollapseTwin() {
        for mirrored in [false, true] {
            for flipped in [false, true] {
                XCTAssertFalse(
                    [
                        "arrow.up.right.and.arrow.down.left",
                        "arrow.down.right.and.arrow.up.left"
                    ].contains(corner(mirrored: mirrored, flipped: flipped).glyphName),
                    "mirrored=\(mirrored) flipped=\(flipped) got an inward arrow"
                )
            }
        }
    }

    func testEveryGlyphNameIsARealSymbol() throws {
        #if canImport(AppKit)
        for mirrored in [false, true] {
            for flipped in [false, true] {
                let name = corner(mirrored: mirrored, flipped: flipped).glyphName
                XCTAssertNotNil(
                    NSImage(systemSymbolName: name, accessibilityDescription: nil),
                    "No such SF Symbol: \(name)"
                )
            }
        }
        #endif
    }
}
