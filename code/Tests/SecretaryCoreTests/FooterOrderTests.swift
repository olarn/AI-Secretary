import XCTest
@testable import SecretaryCore

/// How the four panel buttons are arranged along the bottom of the chat.
///
/// Not one cluster: Projects sits alone against the left edge and the other
/// three sit together against the right, with the window's width between them.
final class FooterOrderTests: XCTestCase {
    func testProjectsSitsAloneAndTheOthersAreTogether() {
        XCTAssertEqual(
            footerSlots(),
            [.button(.projects), .gap, .button(.profile), .button(.skills), .button(.settings)]
        )
    }

    /// The row used to reverse when the bubble mirrored, so Settings changed
    /// ends whenever the character wandered near the right of the screen. That
    /// the placement can't reach this function any more is now the type's job —
    /// there is no argument to pass. What is left to guard is the order itself,
    /// which is what a well-meaning "restore the mirroring" change would move.
    func testTheEndsAreAlwaysProjectsAndSettings() {
        XCTAssertEqual(footerSlots().first, .button(.projects))
        XCTAssertEqual(footerSlots().last, .button(.settings))
    }

    func testExactlyOneGapAndAllButtons() {
        let slots = footerSlots()
        XCTAssertEqual(slots.filter { $0 == FooterSlot.gap }.count, 1)
        let buttons = slots.compactMap { slot -> FooterButton? in
            if case .button(let b) = slot { return b }
            return nil
        }
        XCTAssertEqual(Set(buttons), Set(FooterButton.allCases))
    }

    func testTitlesAreTheOnesShown() {
        XCTAssertEqual(FooterButton.projects.title, "Projects")
        XCTAssertEqual(FooterButton.profile.title, "Profile")
        XCTAssertEqual(FooterButton.skills.title, "Skills")
        XCTAssertEqual(FooterButton.settings.title, "Settings")
    }
}
