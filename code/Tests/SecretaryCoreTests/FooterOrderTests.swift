import XCTest
@testable import SecretaryCore

/// How the four panel buttons are arranged along the bottom of the chat.
///
/// Not one cluster: Projects sits alone against one edge and the other three sit
/// together against the opposite edge, with the window's width between them.
final class FooterOrderTests: XCTestCase {
    func testProjectsSitsAloneAndTheOthersAreTogether() {
        XCTAssertEqual(
            footerSlots(tailOnRight: true),
            [.button(.projects), .gap, .button(.profile), .button(.skills), .button(.settings)]
        )
    }

    /// Tail on the left — the bubble sitting to the character's left. The mirror
    /// image of itself, gap included. Moving only the groups
    /// and leaving each group's own order alone would put Profile where
    /// Settings had been.
    func testMirroringReversesEverythingIncludingTheGap() {
        XCTAssertEqual(
            footerSlots(tailOnRight: false),
            [.button(.settings), .button(.skills), .button(.profile), .gap, .button(.projects)]
        )
    }

    /// Whichever way it faces, Projects is the one against the outer edge on
    /// its own, and Settings is the one against the other.
    func testTheEndsHoldTheSameButtonsEitherWay() {
        XCTAssertEqual(footerSlots(tailOnRight: true).first, .button(.projects))
        XCTAssertEqual(footerSlots(tailOnRight: true).last, .button(.settings))
        XCTAssertEqual(footerSlots(tailOnRight: false).first, .button(.settings))
        XCTAssertEqual(footerSlots(tailOnRight: false).last, .button(.projects))
    }

    func testExactlyOneGapAndAllButtons() {
        for tailOnRight in [true, false] {
            let slots = footerSlots(tailOnRight: tailOnRight)
            XCTAssertEqual(slots.filter { $0 == FooterSlot.gap }.count, 1, "tailOnRight=\(tailOnRight)")
            let buttons = slots.compactMap { slot -> FooterButton? in
                if case .button(let b) = slot { return b }
                return nil
            }
            XCTAssertEqual(Set(buttons), Set(FooterButton.allCases), "tailOnRight=\(tailOnRight)")
        }
    }

    func testTitlesAreTheOnesShown() {
        XCTAssertEqual(FooterButton.projects.title, "Projects")
        XCTAssertEqual(FooterButton.profile.title, "Profile")
        XCTAssertEqual(FooterButton.skills.title, "Skills")
        XCTAssertEqual(FooterButton.settings.title, "Settings")
    }
}
