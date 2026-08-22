import XCTest
@testable import SecretaryCore

final class FooterOrderTests: XCTestCase {
    func testProjectsSitsAloneAndTheOthersAreTogether() {
        XCTAssertEqual(
            footerSlots(),
            [.button(.projects), .gap, .button(.profile), .button(.skills), .button(.settings)]
        )
    }

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
