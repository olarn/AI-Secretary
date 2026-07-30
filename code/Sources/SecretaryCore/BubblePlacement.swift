import CoreGraphics

/// Where the speech bubble goes, given where the character is standing.
///
/// Lifted out of `AppDelegate` so it can be checked without a screen. The rule
/// it encodes is not obvious and got this wrong twice: the bubble may flip to
/// the other side of the character to stay on screen, but a flip is only worth
/// making when the other side is actually roomier. Flipping into a *smaller*
/// space just moves the problem — the panel gets clamped back into the screen
/// and lands on top of the character, which is the one thing the bubble must
/// never do, since the character is how the user reaches it.
///
/// Coordinates are AppKit's: y grows upward, origins are bottom-left.
public struct BubblePlacement: Equatable, Sendable {
    public let origin: CGPoint
    /// Tail on the right rather than the left.
    public let isMirrored: Bool
    /// Bubble below the character, tail pointing up.
    public let isFlippedVertically: Bool

    public init(origin: CGPoint, isMirrored: Bool, isFlippedVertically: Bool) {
        self.origin = origin
        self.isMirrored = isMirrored
        self.isFlippedVertically = isFlippedVertically
    }
}

/// Clamps into a range, tolerating an inverted one: a bubble taller than the
/// screen has no valid origin, and the top edge is the less bad end to lose.
private func clamped(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
    min(max(value, lower), max(lower, upper))
}

/// Places the bubble beside and above the character, flipping only when that
/// buys room.
///
/// - Parameters:
///   - character: the character window's frame.
///   - bubble: the size the chat panel currently wants to be.
///   - visibleFrame: the screen area excluding the menu bar and Dock.
///   - tailTipOffset: distance from the bubble's leading edge to the tail tip.
///   - clearance: how far the bubble is pushed sideways off the character.
///   - gap: vertical gap between character and bubble; negative on purpose, so
///     the tail visually touches the avatar inside its padded window.
///   - margin: gap kept from the screen edge.
public func placeBubble(
    character: CGRect,
    bubble: CGSize,
    visibleFrame: CGRect,
    tailTipOffset: CGFloat,
    clearance: CGFloat,
    gap: CGFloat,
    margin: CGFloat
) -> BubblePlacement {
    let centerX = character.midX

    // Measured from the tip inwards, so only one edge is pinned to the
    // character and the other is free: widening the bubble grows it away from
    // the character instead of sliding the tip off it.
    let naturalX = centerX - tailTipOffset + clearance
    let mirrored = naturalX + bubble.width > visibleFrame.maxX - margin
    let originX = clamped(
        mirrored ? centerX - (bubble.width - tailTipOffset) - clearance : naturalX,
        min: visibleFrame.minX + margin,
        max: visibleFrame.maxX - bubble.width - margin
    )

    let topLimit = visibleFrame.maxY - margin
    let bottomLimit = visibleFrame.minY + margin
    let aboveY = character.maxY + gap
    let belowY = character.minY - bubble.height - gap

    // Room each side would give a bubble of any height. Compared rather than
    // just testing "does it fit above", because when it fits neither side the
    // answer is still the roomier one, not always down.
    let roomAbove = topLimit - aboveY
    let roomBelow = (character.minY - gap) - bottomLimit
    let fitsAbove = bubble.height <= roomAbove
    let fitsBelow = bubble.height <= roomBelow
    let flipped = fitsAbove ? false : (fitsBelow || roomBelow > roomAbove)

    let originY = clamped(
        flipped ? belowY : aboveY,
        min: bottomLimit,
        max: topLimit - bubble.height
    )

    return BubblePlacement(
        origin: CGPoint(x: originX, y: originY),
        isMirrored: mirrored,
        isFlippedVertically: flipped
    )
}
