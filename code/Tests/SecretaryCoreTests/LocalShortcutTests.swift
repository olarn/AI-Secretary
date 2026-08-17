import XCTest
@testable import SecretaryCore

/// When ⌘H is this app's to answer.
///
/// These moved from matching a character to matching a key position, because the
/// character is a different one on every keyboard layout — see
/// `handlesHideLocally` for what that cost and how it was measured.
final class LocalShortcutTests: XCTestCase {
    /// kVK_ANSI_H. The key next to G, whatever it happens to type.
    private let h: UInt16 = 4

    func testTakenWhileTheKeyboardIsInOneOfOurWindows() {
        XCTAssertTrue(handlesHideLocally(isOurWindowKey: true, keyCode: h, hasOnlyCommand: true))
    }

    /// The bug this was rewritten for, and the one the old version of this test
    /// only appeared to cover: it compared `"h"` with `"H"` and called that
    /// "layouts". A Thai layout reports `้` for this very key, so the old rule
    /// said ⌘H was not ours and the whole-app Hide silently stopped happening.
    ///
    /// There is no character in this test at all now, which is the point — the
    /// rule cannot be made to depend on one again without changing its type.
    func testTheKeyIsTheSameKeyWhateverItTypes() {
        XCTAssertTrue(handlesHideLocally(isOurWindowKey: true, keyCode: 4, hasOnlyCommand: true))
    }

    /// Typing anywhere else, ⌘H is none of our business — that is the whole
    /// difference between this and the system-wide claim that broke Hide
    /// everywhere.
    func testLeftAloneWhenTheKeyboardIsSomewhereElse() {
        XCTAssertFalse(handlesHideLocally(isOurWindowKey: false, keyCode: h, hasOnlyCommand: true))
    }

    /// ⌘⇧H is Hide Others and ⌥⌘H is something else again. Neither is ours.
    func testOnlyPlainCommandCounts() {
        XCTAssertFalse(handlesHideLocally(isOurWindowKey: true, keyCode: h, hasOnlyCommand: false))
    }

    /// An H with no Command is a letter someone is typing into the message box,
    /// and swallowing it would be worse than the bug.
    func testAPlainLetterIsNotAShortcut() {
        XCTAssertFalse(handlesHideLocally(isOurWindowKey: true, keyCode: h, hasOnlyCommand: false))
    }

    /// Neighbouring keys, by position: J (38), N (45), W (13), Q (12), and
    /// Escape (53), which the other monitor owns.
    func testNoOtherKeyIsClaimed() {
        for keyCode: UInt16 in [38, 45, 13, 12, 53] {
            XCTAssertFalse(
                handlesHideLocally(isOurWindowKey: true, keyCode: keyCode, hasOnlyCommand: true),
                "keyCode=\(keyCode)"
            )
        }
    }
}
