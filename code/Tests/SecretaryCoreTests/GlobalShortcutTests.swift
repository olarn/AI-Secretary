#if canImport(Carbon)
import Carbon.HIToolbox
#endif
import XCTest
@testable import SecretaryCore

final class GlobalShortcutTests: XCTestCase {
    func testNothingIsClaimedWhileTheChatIsClosed() {
        XCTAssertTrue(claimedShortcuts(hasDismissableWindow: false).isEmpty)
    }

    func testEscapeIsClaimedForAnythingDismissable() {
        XCTAssertFalse(claimedShortcuts(hasDismissableWindow: false).contains(.closeChat))
        XCTAssertTrue(claimedShortcuts(hasDismissableWindow: true).contains(.closeChat))
    }

    func testNothingElseIsEverClaimed() {
        for visible in [false, true] {
            XCTAssertTrue(
                claimedShortcuts(hasDismissableWindow: visible).isSubset(of: [.closeChat]),
                "chatVisible=\(visible)"
            )
        }
    }

    func testTheKeysAreTheOnesAdvertised() {
        XCTAssertEqual(GlobalShortcut.closeChat.keyCode, 53, "kVK_Escape")
        XCTAssertEqual(GlobalShortcut.closeChat.modifiers, 0, "no modifiers")
    }

    func testNoClaimedShortcutUsesCommand() {
        for shortcut in GlobalShortcut.allCases {
            XCTAssertEqual(shortcut.modifiers & 0x0100, 0, "\(shortcut) claims Command")
        }
    }

}
