import XCTest
@testable import SecretaryCore

/// When ⌘H is this app's to answer.
final class LocalShortcutTests: XCTestCase {
    func testTakenWhileTheKeyboardIsInOneOfOurWindows() {
        XCTAssertTrue(handlesHideLocally(isOurWindowKey: true, key: "h", hasOnlyCommand: true))
    }

    /// The whole bug: the bubble had the keyboard, the menu bar belonged to the
    /// app behind it, and macOS hid that one instead.
    func testCapitalsAndLayoutsAreTheSameKey() {
        XCTAssertTrue(handlesHideLocally(isOurWindowKey: true, key: "H", hasOnlyCommand: true))
    }

    /// Typing anywhere else, ⌘H is none of our business — that is the whole
    /// difference between this and the system-wide claim that broke Hide
    /// everywhere.
    func testLeftAloneWhenTheKeyboardIsSomewhereElse() {
        XCTAssertFalse(handlesHideLocally(isOurWindowKey: false, key: "h", hasOnlyCommand: true))
    }

    /// ⌘⇧H is Hide Others and ⌥⌘H is something else again. Neither is ours.
    func testOnlyPlainCommandCounts() {
        XCTAssertFalse(handlesHideLocally(isOurWindowKey: true, key: "h", hasOnlyCommand: false))
    }

    /// An "h" with no Command is a letter someone is typing into the message
    /// box, and swallowing it would be worse than the bug.
    func testAPlainLetterIsNotAShortcut() {
        XCTAssertFalse(handlesHideLocally(isOurWindowKey: true, key: "h", hasOnlyCommand: false))
    }

    func testNoOtherKeyIsClaimed() {
        for key in ["j", "n", "w", "q", ""] {
            XCTAssertFalse(
                handlesHideLocally(isOurWindowKey: true, key: key, hasOnlyCommand: true),
                "key=\(key)"
            )
        }
    }
}
