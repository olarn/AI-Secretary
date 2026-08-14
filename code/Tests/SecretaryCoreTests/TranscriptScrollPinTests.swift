import XCTest
@testable import SecretaryCore

/// Reading back through a conversation while the assistant is still typing
/// must not yank the view to the bottom on every token.
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

    /// The reported bug: a scroll-up event is never consumed, so the reader's
    /// own short flick still moves the content natively and is measured a
    /// moment later. That measurement must not read as "already back at the
    /// bottom" just because the flick was short — it is the same gesture that
    /// `readerScrolledUp` already recorded, not a separate return trip. A wide
    /// re-arm threshold used to live in `update` and, being generous by
    /// design, undid every flick shorter than it — which is why scrolling up
    /// sometimes took two or three tries before it stuck.
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

    /// A conversation shorter than the view reports a negative distance.
    func testAShortConversationFollows() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        pin.update(distanceBelowFold: -200)
        XCTAssertTrue(pin.isFollowing)
    }

    /// Sending a message is an explicit "I'm here now" — it wins over wherever
    /// the reader happened to be scrolled, without waiting to be measured.
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

    // MARK: - The reported bug: dragged back down mid-reply

    /// What a streamed reply looks like from in here: the reader scrolls up
    /// once, and then token after token arrives while they read. Nothing the
    /// arriving reply does may put the view back.
    ///
    /// The previous version failed this by a different route — it ignored
    /// measurements for 0.3s after each of its own scrolls, tokens arrived
    /// faster than that, and so following was never switched off for the whole
    /// length of a reply. Whichever way it is written, this is the assertion
    /// that has to hold: only the reader turns it back on.
    func testGrowingContentNeverDragsTheReaderBack() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()

        // The end of the transcript retreating below the fold, token by token.
        [80.0, 140, 260, 500, 900, 1_600].forEach {
            pin.update(distanceBelowFold: $0)
        }

        XCTAssertFalse(pin.isFollowing, "The reader is reading; the reply grew, they didn't move")
    }

    /// The regression to watch for while fixing the above: a table or a code
    /// block arriving while the reader sits at the bottom pushes the end far
    /// below the fold with no input from them, and that must not be mistaken
    /// for scrolling away.
    func testABlockArrivingAtTheBottomKeepsFollowing() {
        var pin = TranscriptScrollPin()
        pin.update(distanceBelowFold: 600)
        XCTAssertTrue(pin.isFollowing, "Nobody scrolled — that was the content growing")
    }

    // MARK: - When the view has to scroll back to the end

    /// The case this was written for: the running commentary is an entry
    /// *above* the reply being written and it grows in place, so every step of
    /// a tool run pushed the newest text further out of sight while the number
    /// of messages and the length of the last one — all the old trigger
    /// watched — stayed exactly the same.
    func testTheEndBeingPushedOutOfSightAsksForAScroll() {
        let pin = TranscriptScrollPin()
        XCTAssertTrue(pin.isBehind(distanceBelowFold: 18),
                      "Following, and the end is below the fold — put it back")
    }

    /// Where following already put it. Scrolling again would move nothing, and
    /// asking for it on every layout pass is how a scroll and a measurement
    /// chase each other.
    func testTheEndSittingAtTheBottomEdgeAsksForNothing() {
        let pin = TranscriptScrollPin()
        XCTAssertFalse(pin.isBehind(distanceBelowFold: 0))
        XCTAssertFalse(pin.isBehind(distanceBelowFold: TranscriptScrollPin.settled))
    }

    /// A transcript shorter than the view: the end sits well above the bottom
    /// edge and there is nowhere to scroll to.
    func testAnEndAboveTheBottomEdgeAsksForNothing() {
        XCTAssertFalse(TranscriptScrollPin().isBehind(distanceBelowFold: -200))
    }

    /// The whole point of the pin: someone reading back is not dragged to the
    /// bottom, however far below the fold the end has gone.
    func testAReaderWhoScrolledBackIsNotScrolledAnywhere() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        XCTAssertFalse(pin.isBehind(distanceBelowFold: 600))
    }

    /// `isBehind` and `update` share one threshold now — see `update`'s doc
    /// for why the second, wider one they used to have was the bug rather
    /// than a legitimate second question. Below `settled` and following stays
    /// or resumes without a scroll; anything past it is still out of place.
    func testDriftPastSettledIsStillOutOfPlace() {
        let pin = TranscriptScrollPin()
        XCTAssertTrue(pin.isBehind(distanceBelowFold: TranscriptScrollPin.settled + 1),
                      "Past settled is still out of place, and gets put back")
    }

    // MARK: - Which scrolls are the reader taking over

    func testScrollingBackThroughTheConversationIsTakingOver() {
        XCTAssertTrue(readerIsScrollingBack(scrollingDeltaY: 12))
    }

    /// Scrolling down is either asking for more of what is arriving or the way
    /// back to the bottom. Reading it as taking over would stop following at
    /// the moment it is wanted most.
    func testScrollingFurtherDownIsNot() {
        XCTAssertFalse(readerIsScrollingBack(scrollingDeltaY: -12))
    }

    func testAScrollThatMovedNothingIsNot() {
        XCTAssertFalse(readerIsScrollingBack(scrollingDeltaY: 0),
                       "Momentum tails and horizontal scrolls report zero")
    }
}
