import XCTest
@testable import SecretaryCore

/// Which character Esc acts on, and what it does to her.
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
        dismissable: Bool = true,
        visible: Bool = true
    ) -> DismissCandidate {
        DismissCandidate(
            id: id,
            holdsKeyboard: keyboard,
            hasDismissable: dismissable,
            isCharacterVisible: visible
        )
    }

    // MARK: - The hot key: putting windows away, from anywhere

    func testNobodyIsUpAndNothingIsDismissed() {
        XCTAssertNil(dismissDecision([]))
        XCTAssertNil(dismissDecision([candidate(miku, dismissable: false)]))
    }

    func testTheCharacterYouAreTypingInWins() {
        let decision = dismissDecision([
            candidate(miku),
            candidate(anya, keyboard: true),
            candidate(ditto),
        ])

        XCTAssertEqual(decision, DismissDecision(id: anya, step: .dismissWindow))
    }

    /// The whole bug, as a test. Typing in the third character's bubble and
    /// pressing Esc used to ask the first character to close a chat she was not
    /// even showing, so the key that had always put the chat away did nothing.
    func testEscDoesNotGoToTheFirstCharacterJustForBeingFirst() {
        let decision = dismissDecision([
            candidate(miku, dismissable: false),
            candidate(anya, dismissable: false),
            candidate(ditto, keyboard: true),
        ])

        XCTAssertEqual(decision?.id, ditto)
    }

    /// Esc is claimed system-wide, so it arrives while the person is typing in
    /// another app entirely — nobody here holds the keyboard, and it still has
    /// to put the bubble away.
    func testWithNobodyTypingItGoesToWhoeverHasSomethingToPutAway() {
        let decision = dismissDecision([
            candidate(miku, dismissable: false),
            candidate(anya),
            candidate(ditto),
        ])

        XCTAssertEqual(decision?.id, anya)
    }

    /// Holding the keyboard is not enough on its own: a character whose chat is
    /// closed has nothing for Esc to do, and it should reach one who does.
    func testAKeyWindowWithNothingToDismissDoesNotSwallowTheKey() {
        let decision = dismissDecision([
            candidate(miku, keyboard: true, dismissable: false),
            candidate(anya),
        ])

        XCTAssertEqual(decision?.id, anya)
    }

    // MARK: - Esc with the chat already closed

    func testWithNothingLeftToPutAwayEscHidesTheCharacterYouAreIn() {
        let decision = dismissDecision(
            [candidate(miku, keyboard: true, dismissable: false)],
            trigger: .ownWindow
        )

        XCTAssertEqual(decision, DismissDecision(id: miku, step: .hideCharacter))
    }

    /// The rule that keeps a companion from vanishing because somebody
    /// dismissed a dialog in another app: the system-wide claim may put windows
    /// away and nothing else.
    func testTheSystemWideKeyNeverHidesACharacter() {
        XCTAssertNil(dismissDecision(
            [candidate(miku, keyboard: true, dismissable: false)],
            trigger: .hotKey
        ))
    }

    /// Two handlers, one owner. While anything is dismissable the hot key is
    /// registered and consumes the key, so a local press must decline rather
    /// than act — otherwise one press closes the chat *and* hides her.
    func testALocalPressDeclinesWhileTheHotKeyIsTheOneClaimed() {
        XCTAssertNil(dismissDecision(
            [candidate(miku, keyboard: true, dismissable: true)],
            trigger: .ownWindow
        ))
        XCTAssertNil(dismissDecision(
            [
                candidate(miku, keyboard: true, dismissable: false),
                candidate(anya, dismissable: true),
            ],
            trigger: .ownWindow
        ))
    }

    /// Only the character being typed in. Hiding whichever one happens to be
    /// first would take a character off the desktop that the key had nothing to
    /// do with.
    func testEscHidesOnlyTheCharacterHoldingTheKeyboard() {
        XCTAssertNil(dismissDecision(
            [
                candidate(miku, dismissable: false),
                candidate(anya, dismissable: false),
            ],
            trigger: .ownWindow
        ))
    }

    /// A character already hidden has nothing to hide, and the key belongs to
    /// whatever the person does next rather than to us.
    func testAnAlreadyHiddenCharacterDoesNotSwallowTheKey() {
        XCTAssertNil(dismissDecision(
            [candidate(miku, keyboard: true, dismissable: false, visible: false)],
            trigger: .ownWindow
        ))
    }
}
