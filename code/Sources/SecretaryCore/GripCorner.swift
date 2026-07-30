/// Which corner of the chat bubble the resize grip sits in.
///
/// Pulled out of the view so the rule can be pinned down by tests: the grip has
/// to be in the corner the bubble grows out of, and that corner moves as the
/// bubble mirrors and flips. Get it wrong and the gesture argues with itself —
/// you drag away from the empty space you are trying to fill.
public struct GripCorner: Equatable, Sendable {
    /// Bottom edge rather than top.
    public let isBottom: Bool
    /// Leading edge rather than trailing.
    public let isLeading: Bool

    public init(isBottom: Bool, isLeading: Bool) {
        self.isBottom = isBottom
        self.isLeading = isLeading
    }

    /// The grip goes opposite the tail horizontally and on whichever horizontal
    /// edge is free to move vertically. Both are the edges the bubble grows into,
    /// which is what makes "drag it the way you want the box to extend" and the
    /// usual corner-handle reading of "drag away from the box" the same gesture.
    public static func forBubble(isMirrored: Bool, isFlippedVertically: Bool) -> GripCorner {
        GripCorner(isBottom: isFlippedVertically, isLeading: isMirrored)
    }

    /// The SF Symbol whose arrows already lie along this corner's own diagonal,
    /// pointing out of it. Named rather than produced by rotating one glyph: a
    /// rotated symbol is a symbol drawn at an angle it was not hinted for, and
    /// "which way does this arrow point" is exactly the thing the grip has to say
    /// without ambiguity. Two corners share each diagonal — a double-headed arrow
    /// reads the same from both ends.
    ///
    /// Each diagonal has an inward twin whose name is the same two words in the
    /// other order: `arrow.up.right.and.arrow.down.left` draws the arrows meeting
    /// in the middle, which reads as "collapse". The name lists the directions the
    /// heads point, so the outward one names the corner's own two directions.
    public var glyphName: String {
        isBottom == isLeading
            ? "arrow.down.left.and.arrow.up.right"
            : "arrow.up.left.and.arrow.down.right"
    }
}
