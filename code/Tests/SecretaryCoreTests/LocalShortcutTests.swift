import XCTest
@testable import SecretaryCore

final class LocalShortcutTests: XCTestCase {
    private let h: UInt16 = 4

    func testTakenWhileTheKeyboardIsInOneOfOurWindows() {
        XCTAssertTrue(handlesHideLocally(isOurWindowKey: true, keyCode: h, hasOnlyCommand: true))
    }

    func testTheKeyIsTheSameKeyWhateverItTypes() {
        XCTAssertTrue(handlesHideLocally(isOurWindowKey: true, keyCode: 4, hasOnlyCommand: true))
    }

    func testLeftAloneWhenTheKeyboardIsSomewhereElse() {
        XCTAssertFalse(handlesHideLocally(isOurWindowKey: false, keyCode: h, hasOnlyCommand: true))
    }

    func testOnlyPlainCommandCounts() {
        XCTAssertFalse(handlesHideLocally(isOurWindowKey: true, keyCode: h, hasOnlyCommand: false))
    }

    func testAPlainLetterIsNotAShortcut() {
        XCTAssertFalse(handlesHideLocally(isOurWindowKey: true, keyCode: h, hasOnlyCommand: false))
    }

    func testNoOtherKeyIsClaimed() {
        for keyCode: UInt16 in [38, 45, 13, 12, 53] {
            XCTAssertFalse(
                handlesHideLocally(isOurWindowKey: true, keyCode: keyCode, hasOnlyCommand: true),
                "keyCode=\(keyCode)"
            )
        }
    }
}
