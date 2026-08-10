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

    /// The end of the transcript lands a layout pass before the scroll that
    /// follows it, so "on screen" has to allow a line's worth of slack.
    func testJustBelowTheFoldStillCountsAsTheEnd() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        pin.update(distanceBelowFold: TranscriptScrollPin.tolerance - 1)
        XCTAssertTrue(pin.isFollowing)
    }

    func testFurtherBelowTheFoldDoesNot() {
        var pin = TranscriptScrollPin()
        pin.readerScrolledUp()
        pin.update(distanceBelowFold: TranscriptScrollPin.tolerance + 1)
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
