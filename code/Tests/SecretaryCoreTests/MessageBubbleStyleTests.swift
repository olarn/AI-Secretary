import XCTest
@testable import SecretaryCore

/// How the thread is arranged: your messages against one edge, the Secretary's
/// against the other, activity neither.
final class MessageBubbleStyleTests: XCTestCase {
    func testYourMessagesSitAgainstTheTrailingEdgeAndAreTinted() {
        let style = messageBubbleStyle(speaker: .user, kind: .message)
        XCTAssertEqual(style.side, .trailing)
        XCTAssertTrue(style.isMine)
        XCTAssertTrue(style.isBubble)
    }

    func testTheSecretarysMessagesSitAgainstTheLeadingEdge() {
        let style = messageBubbleStyle(speaker: .secretary, kind: .message)
        XCTAssertEqual(style.side, .leading)
        XCTAssertFalse(style.isMine)
        XCTAssertTrue(style.isBubble)
    }

    /// The two sides are opposite each other — that is the whole device, so it
    /// is asserted rather than left to the two cases above happening to differ.
    func testTheTwoSpeakersAreNeverOnTheSameSide() {
        XCTAssertNotEqual(
            messageBubbleStyle(speaker: .user, kind: .message).side,
            messageBubbleStyle(speaker: .secretary, kind: .message).side
        )
    }

    /// Activity is a report of what happened, not something anyone said. It
    /// keeps its full-width dashed box; bubbling it would make it look like an
    /// answer, which is what that styling exists to prevent.
    func testActivityIsNotABubbleWhoeverItCameFrom() {
        for speaker in [TranscriptEntry.Speaker.user, .secretary] {
            let style = messageBubbleStyle(speaker: speaker, kind: .activity)
            XCTAssertFalse(style.isBubble)
            XCTAssertFalse(style.showsSpeakerName)
            XCTAssertEqual(style.side, .leading)
        }
    }

    /// Both speakers are named, because the name is what the time hangs on and
    /// a thread kept across launches has to say when things were said.
    func testBothSpeakersAreNamed() {
        XCTAssertTrue(messageBubbleStyle(speaker: .secretary, kind: .message).showsSpeakerName)
        XCTAssertTrue(messageBubbleStyle(speaker: .user, kind: .message).showsSpeakerName)
    }

    /// A failure sits where the answer would have been, but never looks like
    /// one: it is the app reporting that it couldn't get an answer.
    func testAFailureIsABubbleOnTheSecretarysSideAndMarkedAsOne() {
        let style = messageBubbleStyle(speaker: .secretary, kind: .failure)
        XCTAssertTrue(style.isFailure)
        XCTAssertTrue(style.isBubble)
        XCTAssertEqual(style.side, .leading)
        XCTAssertFalse(style.isMine)
    }

    /// The text of a failure is the most worth pasting elsewhere of anything in
    /// the thread — a terminal, a bug report.
    func testAFailureCanBeCopied() {
        XCTAssertTrue(messageBubbleStyle(speaker: .secretary, kind: .failure).showsCopyButton)
    }

    /// Nothing else is marked as a failure, or the warning colour would stop
    /// meaning anything.
    func testOnlyAFailureIsMarkedAsOne() {
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .message).isFailure)
        XCTAssertFalse(messageBubbleStyle(speaker: .user, kind: .message).isFailure)
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .activity).isFailure)
    }

    /// Only what the Secretary said can be copied — you already have what you
    /// typed.
    func testOnlyTheSecretarysAnswersOfferACopyButton() {
        XCTAssertTrue(messageBubbleStyle(speaker: .secretary, kind: .message).showsCopyButton)
        XCTAssertFalse(messageBubbleStyle(speaker: .user, kind: .message).showsCopyButton)
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .activity).showsCopyButton)
    }


    /// A divider borrows activity's plain look but must not borrow its
    /// heading. "Working / New conversation." was the first thing on screen
    /// after `/new` cleared it — the app announcing it was busy at the one
    /// moment it had just stopped everything.
    func testOnlyActivityIsHeadedWorking() {
        XCTAssertTrue(messageBubbleStyle(speaker: .secretary, kind: .activity).showsWorkingLabel)
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .divider).showsWorkingLabel)
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .message).showsWorkingLabel)
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .failure).showsWorkingLabel)
    }

    /// The two still share everything else — the divider is drawn as bare
    /// unattributed text, not as something anyone said.
    func testADividerIsStillDrawnLikeCommentaryRatherThanAMessage() {
        let divider = messageBubbleStyle(speaker: .secretary, kind: .divider)
        XCTAssertFalse(divider.isBubble)
        XCTAssertFalse(divider.showsSpeakerName)
        XCTAssertEqual(divider.side, .leading)
    }

    func testTheGutterGrowsWithThePanel() {
        XCTAssertLessThan(
            messageBubbleGutter(panelWidth: 360),
            messageBubbleGutter(panelWidth: 700)
        )
    }

    /// Both ends are held: a narrow panel still shows the offset, and a wide one
    /// doesn't hand a sixth of itself to empty space.
    func testTheGutterIsFlooredAndCapped() {
        XCTAssertEqual(messageBubbleGutter(panelWidth: 100), 28)
        XCTAssertEqual(messageBubbleGutter(panelWidth: 4000), 160)
    }

    /// However wide the panel, the message keeps most of it. A gutter that grew
    /// past half would leave the bubble narrower than the empty space beside it.
    func testTheGutterNeverTakesMoreThanAQuarterOfThePanel() {
        for width in [320.0, 480.0, 700.0, 1200.0] {
            XCTAssertLessThan(messageBubbleGutter(panelWidth: width), width * 0.25, "width=\(width)")
        }
    }
}
