import CoreGraphics

/// Where the character stands the first time it appears.
///
/// A rule the app has to decide, so it lives here rather than in the delegate:
/// `AISecretaryApp` is never linked into the test bundle, and a launch position
/// can only be checked by launching.
public enum CharacterLaunch {
    /// Distance in from the right edge of the usable area.
    public static let insetFromRight: Double = 160

    /// How high the character used to stand above the bottom of the usable area.
    public static let restingHeight: Double = 120

    /// Taken off that, as a fraction of the usable height — the character was
    /// asked to stand lower. Expressed against the screen rather than as a fixed
    /// number of points because "how high up the screen it looks" is what
    /// changes with the display, and a constant that reads right on one screen
    /// reads wrong on the next.
    public static let lowering: Double = 0.10

    /// - Parameters:
    ///   - characterSize: the panel's size, so the clamp keeps all of it visible.
    ///   - visibleFrame: the area left over by the Dock and the menu bar, which
    ///     is what the resting position is measured from.
    ///   - screenFrame: the whole display. The clamp uses this, not the visible
    ///     frame, so that launch agrees with `keepCharacterOnScreen`: standing
    ///     on the Dock is a normal place for a desktop character, and the only
    ///     rule is that it must not end up off the screen.
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

    /// Low wins if the two cross — a character taller than the screen is pinned
    /// to the bottom rather than to a negative height above it.
    private static func clamp(_ value: Double, low: Double, high: Double) -> Double {
        min(max(value, low), max(low, high))
    }
}
