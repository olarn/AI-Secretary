import XCTest
@testable import SecretaryCore

/// How the three panel buttons are arranged along the bottom of the chat.
///
/// Not one cluster: Projects sits alone against one edge and the other two sit
/// together against the opposite edge, with the window's width between them.
final class FooterOrderTests: XCTestCase {
    func testProjectsSitsAloneAndTheOtherTwoAreTogether() {
        XCTAssertEqual(
            footerSlots(mirrored: false),
            [.button(.projects), .gap, .button(.profile), .button(.settings)]
        )
    }

    /// The mirror image of itself — the gap moves too. Moving only the groups
    /// and leaving each group's own order alone would put Profile where
    /// Settings had been.
    func testMirroringReversesEverythingIncludingTheGap() {
        XCTAssertEqual(
            footerSlots(mirrored: true),
            [.button(.settings), .button(.profile), .gap, .button(.projects)]
        )
    }

    /// Whichever way it faces, Projects is the one against the outer edge on
    /// its own, and Settings is the one against the other.
    func testTheEndsHoldTheSameButtonsEitherWay() {
        XCTAssertEqual(footerSlots(mirrored: false).first, .button(.projects))
        XCTAssertEqual(footerSlots(mirrored: false).last, .button(.settings))
        XCTAssertEqual(footerSlots(mirrored: true).first, .button(.settings))
        XCTAssertEqual(footerSlots(mirrored: true).last, .button(.projects))
    }

    func testExactlyOneGapAndAllThreeButtons() {
        for mirrored in [false, true] {
            let slots = footerSlots(mirrored: mirrored)
            XCTAssertEqual(slots.filter { $0 == .gap }.count, 1, "mirrored=\(mirrored)")
            let buttons = slots.compactMap { slot -> FooterButton? in
                if case .button(let b) = slot { return b }
                return nil
            }
            XCTAssertEqual(Set(buttons), Set(FooterButton.allCases), "mirrored=\(mirrored)")
        }
    }

    func testTitlesAreTheOnesShown() {
        XCTAssertEqual(FooterButton.projects.title, "Projects")
        XCTAssertEqual(FooterButton.profile.title, "Profile")
        XCTAssertEqual(FooterButton.settings.title, "Settings")
    }
}
