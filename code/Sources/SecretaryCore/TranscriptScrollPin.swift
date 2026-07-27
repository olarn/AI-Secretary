import Foundation

/// Whether the transcript should follow new output.
///
/// Reading back through a conversation while the assistant is still typing is
/// a normal thing to do, and being yanked to the bottom mid-sentence makes it
/// impossible. So the view follows new output only while the reader is already
/// at the bottom, and starts following again the moment they scroll back down.
///
/// Kept here, apart from the view, because it's a small rule with edges worth
/// testing: the tolerance, what happens before the first measurement, and the
/// fact that sending a message should always bring you back.
public struct TranscriptScrollPin: Equatable, Sendable {
    /// How far from the bottom still counts as "at the bottom", in points.
    /// Some slack is needed: partial rows and sub-pixel layout mean an
    /// apparently-bottomed scroll view is rarely at exactly zero.
    public static let tolerance: Double = 24

    /// Follows by default — a fresh conversation is at the bottom already.
    public private(set) var isFollowing = true

    public init() {}

    /// Call whenever the scroll position changes.
    public mutating func update(distanceFromBottom: Double) {
        isFollowing = distanceFromBottom <= Self.tolerance
    }

    /// The reader just did something that means they want to be at the bottom —
    /// sending a message, for instance. Their own action overrides where they
    /// happened to be scrolled.
    public mutating func follow() {
        isFollowing = true
    }
}
