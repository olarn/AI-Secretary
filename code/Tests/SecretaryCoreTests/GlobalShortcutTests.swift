#if canImport(Carbon)
import Carbon.HIToolbox
#endif
import XCTest
@testable import SecretaryCore

/// Which keys the app takes away from the rest of the system.
///
/// Worth a test out of proportion to its size: every shortcut claimed here stops
/// working in every other app on the machine, so the set has to be deliberate
/// and stay that way.
final class GlobalShortcutTests: XCTestCase {
    func testHideIsClaimedWhetherOrNotTheChatIsOpen() {
        XCTAssertTrue(claimedShortcuts(chatVisible: false).contains(.hideApp))
        XCTAssertTrue(claimedShortcuts(chatVisible: true).contains(.hideApp))
    }

    /// The mitigation that keeps this from being hostile. Esc cancels dialogs,
    /// leaves full screen and ends a slideshow; holding it while the chat is
    /// closed would break all of that to serve a window that isn't showing.
    func testEscapeIsHandedBackWhenTheChatIsClosed() {
        XCTAssertFalse(claimedShortcuts(chatVisible: false).contains(.closeChat))
        XCTAssertTrue(claimedShortcuts(chatVisible: true).contains(.closeChat))
    }

    func testNothingElseIsEverClaimed() {
        for visible in [false, true] {
            XCTAssertTrue(
                claimedShortcuts(chatVisible: visible)
                    .isSubset(of: [.hideApp, .closeChat]),
                "chatVisible=\(visible)"
            )
        }
    }

    /// Carbon takes raw virtual key codes, so a typo is a shortcut on the wrong
    /// key that still registers happily.
    func testTheKeysAreTheOnesAdvertised() {
        XCTAssertEqual(GlobalShortcut.hideApp.keyCode, 4, "kVK_ANSI_H")
        XCTAssertEqual(GlobalShortcut.hideApp.modifiers, 0x0100, "cmdKey")
        XCTAssertEqual(GlobalShortcut.closeChat.keyCode, 53, "kVK_Escape")
        XCTAssertEqual(GlobalShortcut.closeChat.modifiers, 0, "no modifiers")
    }

    #if canImport(Carbon)
    /// The modifier constant is spelled out rather than imported, so pin it to
    /// the real one.
    func testTheModifierMatchesCarbonsOwnConstant() {
        XCTAssertEqual(GlobalShortcut.hideApp.modifiers, UInt32(cmdKey))
    }
    #endif
}

