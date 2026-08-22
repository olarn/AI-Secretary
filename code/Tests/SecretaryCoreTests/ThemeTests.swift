import XCTest
@testable import SecretaryCore

final class ThemeTests: XCTestCase {

    func testEveryTextColourStandsOffEveryGround() {
        var checked = 0
        for (paletteName, palette) in Palette.all {
            for (textName, text) in Palette.textRoles {
                for (groundName, ground) in Palette.groundRoles {
                    let ratio = contrastRatio(palette[keyPath: text], palette[keyPath: ground])
                    checked += 1
                    XCTAssertGreaterThanOrEqual(
                        ratio,
                        Palette.contrastFloor,
                        "\(paletteName): \(textName) on \(groundName) is \(ratio), "
                            + "below the \(Palette.contrastFloor) floor"
                    )
                }
            }
        }
        XCTAssertEqual(
            checked, Palette.all.count * 7 * 9,
            "Every combination, not a sample"
        )
    }

    func testEveryEdgeIsVisibleAgainstEveryGround() {
        for (name, palette) in Palette.all {
            XCTAssertGreaterThanOrEqual(
                contrastRatio(palette.hairline, palette.ground), 1.6,
                "\(name): the hairline disappears into the window"
            )
            for (groundName, ground) in Palette.groundRoles {
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(palette.hairline, palette[keyPath: ground]), 1.3,
                    "\(name): the hairline disappears into \(groundName)"
                )
            }
            XCTAssertGreaterThanOrEqual(
                contrastRatio(palette.panelBorder, palette.ground), 2.5,
                "\(name): the panel's outline disappears into the window"
            )
        }
    }

    func testTheSelectedButtonsLabelStandsOffItsFill() {
        for (name, palette) in Palette.all {
            XCTAssertGreaterThanOrEqual(
                contrastRatio(palette.onAccent, palette.accent),
                Palette.contrastFloor,
                "\(name): the label on the selected button is unreadable"
            )
        }
    }

    func testSystemFollowsTheSystemAndTheOthersDoNot() {
        XCTAssertEqual(palette(for: .system, systemIsDark: true), .dark)
        XCTAssertEqual(palette(for: .system, systemIsDark: false), .light)
        XCTAssertEqual(palette(for: .dark, systemIsDark: false), .dark)
        XCTAssertEqual(palette(for: .light, systemIsDark: true), .light)
    }

    func testTheControlAppearanceMatchesTheGround() {
        for (name, palette) in Palette.all {
            let groundIsDark = palette.ground.relativeLuminance < 0.5
            XCTAssertEqual(
                palette.prefersDarkControls, groundIsDark,
                "\(name): the controls would be lit the opposite way to the window"
            )
        }
    }

    func testLuminanceAndRatioAreTheStandardOnes() {
        XCTAssertEqual(ThemeColor(1, 1, 1).relativeLuminance, 1, accuracy: 0.0001)
        XCTAssertEqual(ThemeColor(0, 0, 0).relativeLuminance, 0, accuracy: 0.0001)
        XCTAssertEqual(contrastRatio(ThemeColor(1, 1, 1), ThemeColor(0, 0, 0)), 21, accuracy: 0.01)
        XCTAssertEqual(contrastRatio(ThemeColor(0.5, 0.5, 0.5), ThemeColor(0.5, 0.5, 0.5)), 1)
    }

    func testEveryChoiceIsOfferedWithSomethingToRead() {
        XCTAssertEqual(ThemeChoice.allCases.count, 3)
        for choice in ThemeChoice.allCases {
            XCTAssertFalse(choice.label.isEmpty)
            XCTAssertFalse(choice.explanation.isEmpty)
        }
    }
}
