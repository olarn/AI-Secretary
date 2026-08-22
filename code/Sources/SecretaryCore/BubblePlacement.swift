import CoreGraphics

public struct BubblePlacement: Equatable, Sendable {
    public let origin: CGPoint
    public let isMirrored: Bool
    public let isFlippedVertically: Bool

    public init(origin: CGPoint, isMirrored: Bool, isFlippedVertically: Bool) {
        self.origin = origin
        self.isMirrored = isMirrored
        self.isFlippedVertically = isFlippedVertically
    }
}

public let bubbleScreenMargin: CGFloat = 8

public func usableBubbleWidth(_ visibleFrameWidth: CGFloat) -> CGFloat {
    visibleFrameWidth - bubbleScreenMargin * 2
}

private func clamped(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
    min(max(value, lower), max(lower, upper))
}

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
