import XCTest
@testable import SecretaryCore

/// The panel used to be translucent, so how readable it was depended on the
/// user's wallpaper. These are the checks that say it no longer can.
final class ThemeTests: XCTestCase {

    /// The one that matters. Every text colour, on every ground it can be drawn
    /// on, in every palette — 168 pairs today, and more the moment a role or a
    /// palette is added, without this test being touched.
    ///
    /// Written as a sweep rather than a handful of chosen pairs because the
    /// pair that broke in the shipped app was not one anybody would have
    /// chosen: muted text on the panel ground.
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
        XCTAssertEqual(checked, 3 * 7 * 9, "Every combination, not a sample")
    }

    /// An edge is allowed to be quieter than text, but it still has to be
    /// visible — a hairline the same colour as what it separates is not a
    /// hairline.
    ///
    /// Against *every* ground, not just the window, and that is the
    /// load-bearing part: a code block inside a bubble is nearly the same fill
    /// as the bubble (one neutral cannot stand off both a blue tint and a grey
    /// one), so the edge is the only thing separating them. If the hairline
    /// fades into any surface, some nested box has no visible boundary at all.
    func testEveryEdgeIsVisibleAgainstEveryGround() {
        for (name, palette) in Palette.all {
            // The window's own surface, which is where most separators are
            // drawn, keeps the original floor.
            XCTAssertGreaterThanOrEqual(
                contrastRatio(palette.hairline, palette.ground), 1.6,
                "\(name): the hairline disappears into the window"
            )
            // The tinted surfaces get a lower one, and the reason is a
            // constraint rather than a concession: one hairline has to work on
            // a blue bubble, a grey bubble, an orange card and a teal card at
            // once, and those sit at different luminances. 1.3 is what a single
            // colour can reach against all of them; anything higher here can
            // only be met by giving up having one hairline.
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

    /// The selected footer button is the one place a role is drawn on another
    /// role rather than on a ground, so it is the one pair the sweep above
    /// cannot see.
    func testTheSelectedButtonsLabelStandsOffItsFill() {
        for (name, palette) in Palette.all {
            XCTAssertGreaterThanOrEqual(
                contrastRatio(palette.onAccent, palette.accent),
                Palette.contrastFloor,
                "\(name): the label on the selected button is unreadable"
            )
        }
    }

    /// Contrast is what the user asked for, so the option named after it has to
    /// actually deliver more of it than the one it is an alternative to.
    func testContrastPushesFurtherApartThanPlainDark() {
        XCTAssertGreaterThan(
            contrastRatio(Palette.contrast.mutedText, Palette.contrast.ground),
            contrastRatio(Palette.dark.mutedText, Palette.dark.ground)
        )
        XCTAssertGreaterThan(Palette.contrast.panelBorderWidth, Palette.dark.panelBorderWidth)
    }

    func testSystemFollowsTheSystemAndTheOthersDoNot() {
        XCTAssertEqual(palette(for: .system, systemIsDark: true), .dark)
        XCTAssertEqual(palette(for: .system, systemIsDark: false), .light)
        XCTAssertEqual(palette(for: .dark, systemIsDark: false), .dark)
        XCTAssertEqual(palette(for: .contrast, systemIsDark: false), .contrast)
    }

    /// The window asks AppKit for a matching control appearance, so the caret,
    /// the scroller and the selection tint don't come from the system setting
    /// while everything around them comes from the palette.
    func testTheControlAppearanceMatchesTheGround() {
        for (name, palette) in Palette.all {
            let groundIsDark = palette.ground.relativeLuminance < 0.5
            XCTAssertEqual(
                palette.prefersDarkControls, groundIsDark,
                "\(name): the controls would be lit the opposite way to the window"
            )
        }
    }

    /// Known values, so a typo in a component is a failing test rather than a
    /// slightly different grey.
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
