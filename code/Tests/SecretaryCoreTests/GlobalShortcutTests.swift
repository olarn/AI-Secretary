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
    /// ⌘H must stay an ordinary per-app shortcut. Claiming it took Hide away
    /// from every other app on the machine — reported within minutes of the
    /// build landing, and the reason this file now claims as little as possible.
    func testNothingIsClaimedWhileTheChatIsClosed() {
        XCTAssertTrue(claimedShortcuts(hasDismissableWindow: false).isEmpty)
    }

    /// The mitigation that keeps this from being hostile. Esc cancels dialogs,
    /// leaves full screen and ends a slideshow; holding it while the chat is
    /// closed would break all of that to serve a window that isn't showing.
    /// A pinned pane counts too: with the chat closed and a pane on screen, Esc
    /// still has something to put away.
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

    /// Carbon takes raw virtual key codes, so a typo is a shortcut on the wrong
    /// key that still registers happily.
    func testTheKeysAreTheOnesAdvertised() {
        XCTAssertEqual(GlobalShortcut.closeChat.keyCode, 53, "kVK_Escape")
        XCTAssertEqual(GlobalShortcut.closeChat.modifiers, 0, "no modifiers")
    }

    /// Guards the fix directly: no claimed shortcut may carry Command. Those are
    /// the combinations other apps' menus own.
    func testNoClaimedShortcutUsesCommand() {
        for shortcut in GlobalShortcut.allCases {
            XCTAssertEqual(shortcut.modifiers & 0x0100, 0, "\(shortcut) claims Command")
        }
    }

}

