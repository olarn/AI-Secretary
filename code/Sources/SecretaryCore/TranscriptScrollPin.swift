import Foundation

/// Whether the transcript should follow new output.
///
/// Reading back through a conversation while the assistant is still typing is
/// a normal thing to do, and being yanked to the bottom mid-sentence makes it
/// impossible. So the view follows new output only while the reader is already
/// at the bottom, and starts following again the moment they scroll back down.
///
/// The subtlety is that a scrolling view can't tell who moved it. When the app
/// scrolls to follow a streamed reply, the position it measures during that
/// movement reads as "at the bottom" — which re-latches following even if the
/// reader had just scrolled away, and drags them back down on the next token.
/// So measurements are ignored for a moment after the app scrolls itself.
///
/// Kept apart from the view because those edges are worth testing and the
/// SwiftUI plumbing around it isn't testable here.
public struct TranscriptScrollPin: Equatable, Sendable {
    /// How far from the bottom still counts as "at the bottom", in points.
    /// Some slack is needed: partial rows and sub-pixel layout mean an
    /// apparently-bottomed scroll view is rarely at exactly zero.
    public static let tolerance: Double = 24

    /// How long to disregard measurements after scrolling ourselves — long
    /// enough to cover the movement, short enough that a reader who scrolls
    /// away immediately afterwards is still noticed.
    public static let settleWindow: TimeInterval = 0.3

    /// Follows by default — a fresh conversation is at the bottom already.
    public private(set) var isFollowing = true

    private var ignoringUntil: Date?

    public init() {}

    /// Call whenever the scroll position changes. Measurements taken while our
    /// own scroll is still settling say nothing about where the reader wants to
    /// be, so they're dropped.
    public mutating func update(distanceFromBottom: Double, now: Date = Date()) {
        if let ignoringUntil, now < ignoringUntil { return }
        self.ignoringUntil = nil
        isFollowing = distanceFromBottom <= Self.tolerance
    }

    /// Call immediately before scrolling the view programmatically.
    public mutating func beginProgrammaticScroll(now: Date = Date()) {
        ignoringUntil = now.addingTimeInterval(Self.settleWindow)
    }

    /// The reader just did something that means they want to be at the bottom —
    /// sending a message, for instance. Their own action overrides where they
    /// happened to be scrolled.
    public mutating func follow() {
        isFollowing = true
        ignoringUntil = nil
    }
}
