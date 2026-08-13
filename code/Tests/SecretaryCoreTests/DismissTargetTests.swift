import XCTest
@testable import SecretaryCore

/// Which character Esc acts on.
///
/// Written because Esc stopped working and nobody could see why: it was wired
/// to the first character in the roster, which is invisible when there is one
/// of her and wrong the moment there are three.
final class DismissTargetTests: XCTestCase {
    private let miku = UUID()
    private let anya = UUID()
    private let ditto = UUID()

    private func candidate(
        _ id: UUID,
        keyboard: Bool = false,
        dismissable: Bool = true
    ) -> DismissCandidate {
        DismissCandidate(id: id, holdsKeyboard: keyboard, hasDismissable: dismissable)
    }

    func testNobodyIsUpAndNothingIsDismissed() {
        XCTAssertNil(dismissTarget([]))
        XCTAssertNil(dismissTarget([candidate(miku, dismissable: false)]))
    }

    func testTheCharacterYouAreTypingInWins() {
        let target = dismissTarget([
            candidate(miku),
            candidate(anya, keyboard: true),
            candidate(ditto),
        ])

        XCTAssertEqual(target, anya)
    }

    /// The whole bug, as a test. Typing in the third character's bubble and
    /// pressing Esc used to ask the first character to close a chat she was not
    /// even showing, so the key that had always put the chat away did nothing.
    func testEscDoesNotGoToTheFirstCharacterJustForBeingFirst() {
        let target = dismissTarget([
            candidate(miku, dismissable: false),
            candidate(anya, dismissable: false),
            candidate(ditto, keyboard: true),
        ])

        XCTAssertEqual(target, ditto)
    }

    /// Esc is claimed system-wide, so it arrives while the person is typing in
    /// another app entirely — nobody here holds the keyboard, and it still has
    /// to put the bubble away.
    func testWithNobodyTypingItGoesToWhoeverHasSomethingToPutAway() {
        let target = dismissTarget([
            candidate(miku, dismissable: false),
            candidate(anya),
            candidate(ditto),
        ])

        XCTAssertEqual(target, anya)
    }

    /// Holding the keyboard is not enough on its own: a character whose chat is
    /// closed has nothing for Esc to do, and it should reach one who does.
    func testAKeyWindowWithNothingToDismissDoesNotSwallowTheKey() {
        let target = dismissTarget([
            candidate(miku, keyboard: true, dismissable: false),
            candidate(anya),
        ])

        XCTAssertEqual(target, anya)
    }
}
