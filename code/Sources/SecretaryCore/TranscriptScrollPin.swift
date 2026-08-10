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
    /// How far past the bottom edge the end of the transcript may sit and still
    /// count as "on screen", in points. Some slack is needed: a token lands one
    /// layout pass before the scroll that follows it, and that pass measures the
    /// end a line below the fold.
    public static let tolerance: Double = 24

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
    /// Only ever latches on. A larger distance is the ambiguous one — it is
    /// what both a reader scrolling up and a reply growing look like — so it is
    /// evidence of nothing and is left alone. The end coming back on screen is
    /// unambiguous.
    public mutating func update(distanceBelowFold: Double) {
        guard distanceBelowFold <= Self.tolerance else { return }
        isFollowing = true
    }

    /// The reader did something that means they want to be at the bottom —
    /// sending a message, for instance, which overrides wherever they happened
    /// to be scrolled.
    public mutating func follow() {
        isFollowing = true
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
