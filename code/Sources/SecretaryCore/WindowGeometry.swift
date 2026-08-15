import CoreGraphics

/// Sizing and placement rules that used to live inline in `AISecretaryApp` —
/// the target the test bundle never links, where a rule can regress without a
/// single test noticing. Each is a pure function; the view or delegate only
/// applies the answer. Same reasoning as `placeBubble` and `GripCorner`.

/// Sized to the content, within reason: a two-row table should not open a
/// window the height of the screen, and a long one should not try to. The
/// 32pt is breathing room around the hosting view's fitting size.
public func infoWindowSize(fitting wanted: CGSize) -> CGSize {
    CGSize(
        width: min(max(wanted.width + 32, 320), 720),
        height: min(max(wanted.height + 32, 180), 640)
    )
}

/// Cascade, so a second window doesn't land exactly on the first — and the
/// ninth starts over at the top rather than marching off the screen.
public func infoWindowOrigin(visibleFrame: CGRect, existingWindows: Int) -> CGPoint {
    let step = 26.0 * CGFloat(existingWindows % 8)
    return CGPoint(
        x: visibleFrame.minX + 120 + step,
        y: visibleFrame.maxY - 80 - step
    )
}

/// The message box grows with the draft, between one line and the line limit.
public func messageBoxHeight(draft: Double, lineHeight: Double, lineLimit: Int) -> Double {
    min(max(draft, lineHeight), lineHeight * Double(lineLimit))
}

/// One free-resize drag of the chat bubble, measured from where it started.
///
/// The edges on the tail's side stay pinned to the character — the tail must
/// not slide off it just because the window got bigger — so the bubble only
/// ever grows into the two opposite edges, and the drag follows those: right
/// and up in the usual position, left when mirrored, down when flipped below
/// the character.
///
/// Everything is captured once, at the start of the drag. Read the layout
/// fresh on every event instead and a layout that flips mid-drag inverts the
/// gesture: keep dragging the same way and the box shrinks, which un-flips
/// it, which grows it again. Measured at the top of the screen, the height
/// oscillated 909 → 801 → 933 → 777 in four events, the swing widening each
/// time. Same reason each step is measured from the one fixed starting point
/// rather than accumulated.
public struct ChatResizeDrag: Equatable, Sendable {
    let pointer: CGPoint
    let width: Double
    let height: Double
    /// Which way the bubble grows, fixed for the whole drag.
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
        // Screen coordinates point up, so this is already "up is taller"
        // unless the bubble sits below the character and grows downward.
        self.growsUp = isFlippedVertically ? -1 : 1
    }

    /// The size the bubble should be with the pointer here.
    public func size(at current: CGPoint) -> CGSize {
        CGSize(
            width: width + (current.x - pointer.x) * growsRight,
            height: height + (current.y - pointer.y) * growsUp
        )
    }
}
