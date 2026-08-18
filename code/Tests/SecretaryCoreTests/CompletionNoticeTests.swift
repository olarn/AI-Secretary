import XCTest
@testable import SecretaryCore

/// When a finished turn earns a banner, and what it says.
///
/// The decision lives in a library target rather than in the notifier because
/// `AISecretaryApp` is never linked into the test bundle — a rule written into
/// the charter after 18 files of it turned out to be invisible to coverage.
final class CompletionNoticeTests: XCTestCase {
    private func turn(
        name: String = "Miku",
        text: String = "Pushed the branch and the tests are green.",
        succeeded: Bool = true,
        errand: Bool = false
    ) -> FinishedTurn {
        FinishedTurn(characterName: name, text: text, succeeded: succeeded, wasErrand: errand)
    }

    func testNotifiesWhenTheChatIsClosed() {
        let notice = completionNotice(for: turn(), isChatVisible: false)

        XCTAssertEqual(notice?.title, "Miku")
        XCTAssertEqual(notice?.body, "Pushed the branch and the tests are green.")
    }

    /// The reply is in a window the person can see. The window is the whole
    /// test — not whether this app happens to be the frontmost one, which the
    /// owner ruled out while driving 0.19.288: a bubble open behind the editor
    /// is still a bubble they can read.
    func testStaysQuietWhileHerChatIsOnScreen() {
        XCTAssertNil(completionNotice(for: turn(), isChatVisible: true))
    }

    /// One request, two finished turns: the character who was handed the errand
    /// answers, and the character who asked finishes again reporting back. Only
    /// the second is the person's.
    func testStaysQuietForAnotherCharactersErrand() {
        XCTAssertNil(
            completionNotice(for: turn(errand: true), isChatVisible: false)
        )
    }

    func testStaysQuietWhenThereIsNothingToSay() {
        XCTAssertNil(
            completionNotice(for: turn(text: "   \n  "), isChatVisible: false)
        )
    }

    /// A failure that nobody sees is worse than a success nobody sees, so it
    /// still notifies — but it must not read as the work having landed.
    func testAFailureSaysSoInTheTitle() {
        let notice = completionNotice(
            for: turn(text: "The build failed.", succeeded: false),
            isChatVisible: false
        )

        XCTAssertEqual(notice?.title, "Miku couldn't finish")
        XCTAssertEqual(notice?.body, "The build failed.")
    }

    func testCollapsesTheReplyOntoOneLine() {
        XCTAssertEqual(noticeBody("# Done\n\n- built\n- tested"), "# Done - built - tested")
    }

    func testTruncatesALongReply() {
        let body = noticeBody(String(repeating: "a", count: 50) + " tail", limit: 20)

        XCTAssertEqual(body, String(repeating: "a", count: 20) + "…")
    }

    func testLeavesAShortReplyWhole() {
        XCTAssertEqual(noticeBody("all good", limit: 20), "all good")
    }
}
