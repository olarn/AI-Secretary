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

    /// Degrees to rotate the ↖↘ glyph so it lies along the corner's own diagonal.
    /// Top-leading and bottom-trailing already do; the other two need a quarter
    /// turn to point ↗↙.
    public var glyphRotation: Double {
        isBottom == isLeading ? 90 : 0
    }
}
