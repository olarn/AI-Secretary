import CoreGraphics

public enum CharacterLaunch {
    public static let insetFromRight: Double = 160

    public static let restingHeight: Double = 120

    public static let lowering: Double = 0.10

    public static func origin(
        characterSize: CGSize,
        visibleFrame: CGRect,
        screenFrame: CGRect
    ) -> CGPoint {
        let x = visibleFrame.maxX - insetFromRight
        let y = visibleFrame.minY + restingHeight - visibleFrame.height * lowering
        return CGPoint(
            x: clamp(x, low: screenFrame.minX, high: screenFrame.maxX - characterSize.width),
            y: clamp(y, low: screenFrame.minY, high: screenFrame.maxY - characterSize.height)
        )
    }

    public static let spacingFraction: Double = 1.4

    public static func origin(
        ordinal: Int,
        characterSize: CGSize,
        visibleFrame: CGRect,
        screenFrame: CGRect
    ) -> CGPoint {
        let first = origin(
            characterSize: characterSize,
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )
        let shifted = first.x - Double(max(0, ordinal)) * characterSize.width * spacingFraction
        return CGPoint(
            x: clamp(shifted, low: screenFrame.minX, high: screenFrame.maxX - characterSize.width),
            y: first.y
        )
    }

    private static func clamp(_ value: Double, low: Double, high: Double) -> Double {
        min(max(value, low), max(low, high))
    }
}
