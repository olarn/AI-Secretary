import XCTest
@testable import SecretaryCore

/// The order of the three panel buttons along the bottom of the chat.
final class FooterOrderTests: XCTestCase {
    /// The owner's arrangement: Projects on the far left, then Profile, with
    /// Settings on the right.
    func testTheDefaultRowReadsProjectsProfileSettings() {
        XCTAssertEqual(
            footerOrder(alignedTrailing: false),
            [.projects, .profile, .settings]
        )
    }

    /// Mirrored, the row hugs the other edge, so the sequence reverses and each
    /// button keeps the same distance from the outer edge it had before. Holding
    /// the literal order instead would move every button under a different
    /// finger depending on which way the bubble happened to flip.
    func testMirroringReversesTheRow() {
        XCTAssertEqual(
            footerOrder(alignedTrailing: true),
            [.settings, .profile, .projects]
        )
    }

    func testTheSameThreeButtonsAppearWhicheverSideItIsOn() {
        XCTAssertEqual(
            Set(footerOrder(alignedTrailing: false)),
            Set(footerOrder(alignedTrailing: true))
        )
        XCTAssertEqual(footerOrder(alignedTrailing: false).count, FooterButton.allCases.count)
    }

    /// Whichever side it is on, the button nearest the outer edge is the same
    /// one — that is what "the order swapped correctly" means here.
    func testProjectsStaysOnTheOutsideOnBothSides() {
        XCTAssertEqual(footerOrder(alignedTrailing: false).first, .projects)
        XCTAssertEqual(footerOrder(alignedTrailing: true).last, .projects)
    }

    func testTitlesAreTheOnesShown() {
        XCTAssertEqual(FooterButton.projects.title, "Projects")
        XCTAssertEqual(FooterButton.profile.title, "Profile")
        XCTAssertEqual(FooterButton.settings.title, "Settings")
    }
}
