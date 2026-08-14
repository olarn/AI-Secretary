import Foundation

/// Whether the transcript should follow new output.
///
/// Reading back through a conversation while the assistant is still typing is
/// a normal thing to do, and being yanked to the bottom mid-sentence makes it
/// impossible. So the view follows new output only while the reader is already
/// at the bottom, and starts following again the moment they scroll back down.
///
/// The subtlety is that a scrolling view can't tell who moved it, and the two
/// things that move it look identical from a position alone: the reader
/// scrolling up, and the content growing under a reader who hasn't moved. Both
/// push the end of the transcript out of sight.
///
/// The first attempt told them apart by time — ignore measurements for a moment
/// after we scroll ourselves — and that is what the bug turned out to be. A
/// streamed reply scrolls on every token, each scroll pushed the window out by
/// another 0.3s, and tokens arrive faster than that, so for the whole length of
/// a reply no measurement was ever read and following could not be switched
/// off. Exactly the case the mechanism existed for.
///
/// So the two are told apart by *source* instead of by timing, which no rate of
/// tokens can defeat:
///
/// - only a scroll the reader performs can stop it following (`readerScrolledUp`),
/// - a measured position can only ever start it again (`update`).
///
/// Growth therefore cannot unlatch following by construction rather than by
/// arithmetic, and there is no clock in here at all — every function below
/// returns the same answer for the same arguments.
public struct TranscriptScrollPin: Equatable, Sendable {
    /// Follows by default — a fresh conversation is at the bottom already.
    public private(set) var isFollowing = true

    public init() {}

    /// Call for a scroll the reader performed themselves, back towards earlier
    /// messages. They are reading; nothing arriving should move the view.
    public mutating func readerScrolledUp() {
        isFollowing = false
    }

    /// Call whenever the end of the transcript is measured against the bottom
    /// edge of the view: positive means it sits below the fold.
    ///
    /// Re-arms only within `settled` of the fold — the same threshold
    /// `isBehind` uses to call the reader already there, not a wider one of
    /// its own. A wider one used to live here, on the theory that "still
    /// basically at the bottom" ought to be more forgiving than "already
    /// exactly at the bottom". It wasn't a free choice: `readerScrolledUp` is
    /// never allowed to consume the scroll event that reported it (see
    /// `startWatchingScroll`), so the reader's own short scroll up still moves
    /// the content, and the very next call here measures that scroll's own
    /// resulting position — not a later, separate trip back down. A short flick
    /// lands well within any generous slack, so a wide threshold undid it on
    /// the spot, which is why scrolling up sometimes took two or three tries
    /// before it held. A reader who genuinely scrolls back down always
    /// converges on the same near-zero rest position `isBehind` already
    /// trusts — the scroll view has nowhere further to give past its own
    /// bottom — so nothing legitimate is lost by asking for that here too.
    public mutating func update(distanceBelowFold: Double) {
        guard distanceBelowFold <= Self.settled else { return }
        isFollowing = true
    }

    /// The reader did something that means they want to be at the bottom —
    /// sending a message, for instance, which overrides wherever they happened
    /// to be scrolled.
    public mutating func follow() {
        isFollowing = true
    }

    /// Closer than this to the bottom edge and the end is already where
    /// following would put it, so scrolling again would move nothing — and, by
    /// the same measure, close enough to count as *at* the bottom in the first
    /// place. One number answers both questions now. Two used to: this one,
    /// strict, for "stop nudging it, it's there"; a much wider one for "still
    /// counts as there" when deciding whether to resume following after a
    /// scroll. The wider one existed to forgive a token landing a layout pass
    /// before the scroll that follows it — but `update` only reads that
    /// forgiveness when following is already on, where it changes nothing, and
    /// it was reached on the one path where it did change something: the
    /// reader's own short scroll up, whose resulting position it forgave right
    /// back into following. See `update` for the rest of that story.
    public static let settled: Double = 0.5

    /// Whether the end of the transcript has been pushed below the bottom edge
    /// while we are supposed to be following it — the whole condition for
    /// scrolling back to the end, decided from the measurement itself.
    ///
    /// This is what replaced watching the transcript for changes. A change
    /// signature has to be able to name every cause of movement in advance, and
    /// the one that shipped could not: it was the number of messages and the
    /// length of the last one, while the running commentary grows *in place*,
    /// in an entry inserted *above* the reply being written. Neither number
    /// moved, so nothing scrolled, and every step of a tool run pushed the
    /// newest text a line further out of sight.
    ///
    /// A position cannot miss a cause. The commentary growing, a viewport that
    /// shrank because an approval card appeared, a font size change, a window
    /// resize — all of them move the end of the content, and this sees them
    /// without knowing which one happened.
    public func isBehind(distanceBelowFold: Double) -> Bool {
        isFollowing && distanceBelowFold > Self.settled
    }
}

/// Whether a scroll wheel/trackpad event is the reader moving back through the
/// conversation.
///
/// Only upwards counts. Scrolling *down* is either asking for more of what is
/// arriving or on the way back to the bottom, and neither is a reason to stop
/// following — while stopping on it would need a second event to undo, at the
/// moment the reader least expects the view to be stuck.
///
/// A free function rather than a method: it is a rule about an event, decided
/// once, in a target the tests can see. The view only applies the answer.
public func readerIsScrollingBack(scrollingDeltaY: Double) -> Bool {
    scrollingDeltaY > 0
}
