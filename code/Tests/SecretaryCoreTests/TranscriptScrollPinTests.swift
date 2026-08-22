import XCTest
@testable import SecretaryCore

final class TranscriptScrollPinTests: XCTestCase {
    func testAFreshConversationFollowsNewOutput() {
        XCTAssertTrue(TranscriptScrollPin().isFollowing,
                      "Nothing to scroll away from yet — following is the sane start")
    }

    func testScrollingBackStopsItFollowing() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        XCTAssertFalse(pin.isFollowing)
    }

    func testComingBackToTheEndResumesFollowing() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        pin.update(distanceBelowFold: 0)
        XCTAssertTrue(pin.isFollowing)
    }

    func testAShortFlickUpDoesNotImmediatelyResumeFollowing() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        pin.update(distanceBelowFold: 15)
        XCTAssertFalse(pin.isFollowing, "This is the flick's own resulting position, not a return to the bottom")
    }

    func testFurtherBelowTheFoldDoesNot() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        pin.update(distanceBelowFold: TranscriptScrollPin.settled + 1)
        XCTAssertFalse(pin.isFollowing, "Still short of the end — nothing to resume from")
    }

    func testAShortConversationFollows() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        pin.update(distanceBelowFold: -200)
        XCTAssertTrue(pin.isFollowing)
    }

    func testSendingAMessageBringsItBack() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        pin.follow()
        XCTAssertTrue(pin.isFollowing)
    }

    func testItCanBeScrolledAwayAgainAfterwards() {
        var pin = TranscriptScrollPin()
        pin.follow()
        pin.readerScrolledUp()
        XCTAssertFalse(pin.isFollowing)
    }

    func testGrowingContentNeverDragsTheReaderBack() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()

        [80.0, 140, 260, 500, 900, 1_600].forEach {
            pin.update(distanceBelowFold: $0)
        }

        XCTAssertFalse(pin.isFollowing, "The reader is reading; the reply grew, they didn't move")
    }

    func testABlockArrivingAtTheBottomKeepsFollowing() {
        var pin = TranscriptScrollPin()
        pin.update(distanceBelowFold: 600)
        XCTAssertTrue(pin.isFollowing, "Nobody scrolled — that was the content growing")
    }

    func testTheEndBeingPushedOutOfSightAsksForAScroll() {
        let pin = TranscriptScrollPin()
        XCTAssertTrue(pin.isBehind(distanceBelowFold: 18),
                      "Following, and the end is below the fold — put it back")
    }

    func testTheEndSittingAtTheBottomEdgeAsksForNothing() {
        let pin = TranscriptScrollPin()
        XCTAssertFalse(pin.isBehind(distanceBelowFold: 0))
        XCTAssertFalse(pin.isBehind(distanceBelowFold: TranscriptScrollPin.settled))
    }

    func testAnEndAboveTheBottomEdgeAsksForNothing() {
        XCTAssertFalse(TranscriptScrollPin().isBehind(distanceBelowFold: -200))
    }

    func testAReaderWhoScrolledBackIsNotScrolledAnywhere() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        XCTAssertFalse(pin.isBehind(distanceBelowFold: 600))
    }

    func testDriftPastSettledIsStillOutOfPlace() {
        let pin = TranscriptScrollPin()
        XCTAssertTrue(pin.isBehind(distanceBelowFold: TranscriptScrollPin.settled + 1),
                      "Past settled is still out of place, and gets put back")
    }

    func testScrollingBackThroughTheConversationIsTakingOver() {
        XCTAssertTrue(readerIsScrollingBack(scrollingDeltaY: 12))
    }

    func testScrollingFurtherDownIsNot() {
        XCTAssertFalse(readerIsScrollingBack(scrollingDeltaY: -12))
    }

    func testAScrollThatMovedNothingIsNot() {
        XCTAssertFalse(readerIsScrollingBack(scrollingDeltaY: 0),
                       "Momentum tails and horizontal scrolls report zero")
    }
}
