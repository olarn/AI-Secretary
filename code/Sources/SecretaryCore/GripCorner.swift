public struct GripCorner: Equatable, Sendable {
    public let isBottom: Bool
    public let isLeading: Bool

    public init(isBottom: Bool, isLeading: Bool) {
        self.isBottom = isBottom
        self.isLeading = isLeading
    }

    public static func forBubble(isMirrored: Bool, isFlippedVertically: Bool) -> GripCorner {
        GripCorner(isBottom: isFlippedVertically, isLeading: isMirrored)
    }

    public var glyphName: String {
        isBottom == isLeading
            ? "arrow.down.left.and.arrow.up.right"
            : "arrow.up.left.and.arrow.down.right"
    }
}
