import XCTest
@testable import SecretaryCore

/// Reading back through a conversation while the assistant is still typing
/// must not yank the view to the bottom on every token.
final class TranscriptScrollPinTests: XCTestCase {
    func testAFreshConversationFollowsNewOutput() {
        XCTAssertTrue(TranscriptScrollPin().isFollowing,
                      "Nothing to scroll away from yet — following is the sane start")
    }

    func testScrollingUpStopsItFollowing() {
        var pin = TranscriptScrollPin()
        pin.update(distanceFromBottom: 400)
        XCTAssertFalse(pin.isFollowing)
    }

    func testComingBackToTheBottomResumesFollowing() {
        var pin = TranscriptScrollPin()
        pin.update(distanceFromBottom: 400)
        pin.update(distanceFromBottom: 0)
        XCTAssertTrue(pin.isFollowing)
    }

    /// A scroll view sitting at the bottom rarely reports exactly zero — partial
    /// rows and sub-pixel layout leave a few points. Without slack the view
    /// would stop following for no visible reason.
    func testASmallGapStillCountsAsTheBottom() {
        var pin = TranscriptScrollPin()
        pin.update(distanceFromBottom: TranscriptScrollPin.tolerance - 1)
        XCTAssertTrue(pin.isFollowing)
    }

    func testJustPastTheToleranceCountsAsScrolledAway() {
        var pin = TranscriptScrollPin()
        pin.update(distanceFromBottom: TranscriptScrollPin.tolerance + 1)
        XCTAssertFalse(pin.isFollowing)
    }

    /// Content shorter than the viewport reports a negative distance.
    func testAShortConversationFollows() {
        var pin = TranscriptScrollPin()
        pin.update(distanceFromBottom: -200)
        XCTAssertTrue(pin.isFollowing)
    }

    /// Sending a message is an explicit "I'm here now" — it should win over
    /// wherever the reader happened to be scrolled.
    func testSendingAMessageBringsItBack() {
        var pin = TranscriptScrollPin()
        pin.update(distanceFromBottom: 900)
        XCTAssertFalse(pin.isFollowing)

        pin.follow()
        XCTAssertTrue(pin.isFollowing)
    }

    /// …but only until the next measurement, so scrolling away again works.
    func testItCanBeScrolledAwayAgainAfterwards() {
        var pin = TranscriptScrollPin()
        pin.follow()
        pin.update(distanceFromBottom: 900)
        XCTAssertFalse(pin.isFollowing)
    }
}
