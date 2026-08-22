import XCTest
@testable import SecretaryCore

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

    func testEscDoesNotGoToTheFirstCharacterJustForBeingFirst() {
        let decision = dismissDecision([
            candidate(miku, dismissable: false),
            candidate(anya, dismissable: false),
            candidate(ditto, keyboard: true),
        ])

        XCTAssertEqual(decision?.id, ditto)
    }

    func testWithNobodyTypingItGoesToWhoeverHasSomethingToPutAway() {
        let decision = dismissDecision([
            candidate(miku, dismissable: false),
            candidate(anya),
            candidate(ditto),
        ])

        XCTAssertEqual(decision?.id, anya)
    }

    func testAKeyWindowWithNothingToDismissDoesNotSwallowTheKey() {
        let decision = dismissDecision([
            candidate(miku, keyboard: true, dismissable: false),
            candidate(anya),
        ])

        XCTAssertEqual(decision?.id, anya)
    }

    func testWithNothingLeftToPutAwayEscHidesTheCharacterYouAreIn() {
        let decision = dismissDecision(
            [candidate(miku, keyboard: true, dismissable: false)],
            trigger: .ownWindow
        )

        XCTAssertEqual(decision, DismissDecision(id: miku, step: .hideCharacter))
    }

    func testTheSystemWideKeyNeverHidesACharacter() {
        XCTAssertNil(dismissDecision(
            [candidate(miku, keyboard: true, dismissable: false)],
            trigger: .hotKey
        ))
    }

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

    func testEscHidesOnlyTheCharacterHoldingTheKeyboard() {
        XCTAssertNil(dismissDecision(
            [
                candidate(miku, dismissable: false),
                candidate(anya, dismissable: false),
            ],
            trigger: .ownWindow
        ))
    }

    func testAnAlreadyHiddenCharacterDoesNotSwallowTheKey() {
        XCTAssertNil(dismissDecision(
            [candidate(miku, keyboard: true, dismissable: false, visible: false)],
            trigger: .ownWindow
        ))
    }
}

final class HasSomethingToDismissTests: XCTestCase {

    func testAnOpenChatCounts() {
        XCTAssertTrue(hasSomethingToDismiss(isChatVisible: true, visiblePanes: 0))
    }

    func testAPaneOnScreenCountsWithTheChatShut() {
        XCTAssertTrue(hasSomethingToDismiss(isChatVisible: false, visiblePanes: 1))
    }

    func testPanesThatExistButAreOffScreenDoNotCount() {
        XCTAssertFalse(hasSomethingToDismiss(isChatVisible: false, visiblePanes: 0))
    }

    func testWithEveryPanePutAwayEscCanReachTheCharacterAgain() {
        let id = UUID()
        let decision = dismissDecision(
            [DismissCandidate(
                id: id,
                holdsKeyboard: true,
                hasDismissable: hasSomethingToDismiss(isChatVisible: false, visiblePanes: 0),
                isCharacterVisible: true
            )],
            trigger: .ownWindow
        )

        XCTAssertEqual(decision, DismissDecision(id: id, step: .hideCharacter))
    }
}
