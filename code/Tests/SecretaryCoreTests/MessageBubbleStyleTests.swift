import XCTest
@testable import SecretaryCore

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

    func testTheTwoSpeakersAreNeverOnTheSameSide() {
        XCTAssertNotEqual(
            messageBubbleStyle(speaker: .user, kind: .message).side,
            messageBubbleStyle(speaker: .secretary, kind: .message).side
        )
    }

    func testActivityIsNotABubbleWhoeverItCameFrom() {
        for speaker in [TranscriptEntry.Speaker.user, .secretary] {
            let style = messageBubbleStyle(speaker: speaker, kind: .activity)
            XCTAssertFalse(style.isBubble)
            XCTAssertFalse(style.showsSpeakerName)
            XCTAssertEqual(style.side, .leading)
        }
    }

    func testBothSpeakersAreNamed() {
        XCTAssertTrue(messageBubbleStyle(speaker: .secretary, kind: .message).showsSpeakerName)
        XCTAssertTrue(messageBubbleStyle(speaker: .user, kind: .message).showsSpeakerName)
    }

    func testAFailureIsABubbleOnTheSecretarysSideAndMarkedAsOne() {
        let style = messageBubbleStyle(speaker: .secretary, kind: .failure)
        XCTAssertTrue(style.isFailure)
        XCTAssertTrue(style.isBubble)
        XCTAssertEqual(style.side, .leading)
        XCTAssertFalse(style.isMine)
    }

    func testAFailureCanBeCopied() {
        XCTAssertTrue(messageBubbleStyle(speaker: .secretary, kind: .failure).showsCopyButton)
    }

    func testOnlyAFailureIsMarkedAsOne() {
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .message).isFailure)
        XCTAssertFalse(messageBubbleStyle(speaker: .user, kind: .message).isFailure)
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .activity).isFailure)
    }

    func testOnlyTheSecretarysAnswersOfferACopyButton() {
        XCTAssertTrue(messageBubbleStyle(speaker: .secretary, kind: .message).showsCopyButton)
        XCTAssertFalse(messageBubbleStyle(speaker: .user, kind: .message).showsCopyButton)
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .activity).showsCopyButton)
    }

    func testOnlyActivityIsHeadedWorking() {
        XCTAssertTrue(messageBubbleStyle(speaker: .secretary, kind: .activity).showsWorkingLabel)
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .divider).showsWorkingLabel)
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .message).showsWorkingLabel)
        XCTAssertFalse(messageBubbleStyle(speaker: .secretary, kind: .failure).showsWorkingLabel)
    }

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

    func testTheGutterIsFlooredAndCapped() {
        XCTAssertEqual(messageBubbleGutter(panelWidth: 100), 28)
        XCTAssertEqual(messageBubbleGutter(panelWidth: 4000), 160)
    }

    func testTheGutterNeverTakesMoreThanAQuarterOfThePanel() {
        for width in [320.0, 480.0, 700.0, 1200.0] {
            XCTAssertLessThan(messageBubbleGutter(panelWidth: width), width * 0.25, "width=\(width)")
        }
    }
}
