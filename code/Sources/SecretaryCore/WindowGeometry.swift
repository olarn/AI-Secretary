import CoreGraphics

public func infoWindowSize(fitting wanted: CGSize) -> CGSize {
    CGSize(
        width: min(max(wanted.width + 32, 320), 720),
        height: min(max(wanted.height + 32, 180), 640)
    )
}

public func infoWindowOrigin(visibleFrame: CGRect, existingWindows: Int) -> CGPoint {
    let step = 26.0 * CGFloat(existingWindows % 8)
    return CGPoint(
        x: visibleFrame.minX + 120 + step,
        y: visibleFrame.maxY - 80 - step
    )
}

public func messageBoxHeight(draft: Double, lineHeight: Double, lineLimit: Int) -> Double {
    min(max(draft, lineHeight), lineHeight * Double(lineLimit))
}

public struct ChatResizeDrag: Equatable, Sendable {
    let pointer: CGPoint
    let width: Double
    let height: Double
    let growsRight: Double
    let growsUp: Double

    public init(
        pointer: CGPoint,
        width: Double,
        height: Double,
        isMirrored: Bool,
        isFlippedVertically: Bool
    ) {
        self.pointer = pointer
        self.width = width
        self.height = height
        self.growsRight = isMirrored ? -1 : 1
        self.growsUp = isFlippedVertically ? -1 : 1
    }

    public func size(at current: CGPoint) -> CGSize {
        CGSize(
            width: width + (current.x - pointer.x) * growsRight,
            height: height + (current.y - pointer.y) * growsUp
        )
    }
}
