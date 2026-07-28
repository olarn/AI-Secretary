import SwiftUI

/// A comic/manga-style speech bubble: a single continuous outline — rounded
/// rectangle body plus a curved, tapered tail — so the tail reads as part of
/// the bubble rather than a shape pasted on top.
///
/// `isMirrored` flips the shape horizontally so the tail can switch from the
/// left side to the right side as the bubble is repositioned to stay
/// on-screen. `isFlippedVertically` flips it so the tail points up from the
/// top edge instead of down from the bottom, for when the bubble has to sit
/// below the character instead of above it. Both keep the tail's base
/// anchored at the same fraction of the edge, so it always aligns with the
/// character regardless of which side/orientation is chosen.
struct SpeechBubbleShape: Shape {
    /// Shared so layout code can reserve exactly this much room for the tail.
    static let defaultTailLength: CGFloat = 30
    /// The drawn tail stops slightly short of the reserved strip so the tip
    /// hovers next to the character instead of poking into it.
    static let tailLengthRatio: CGFloat = 0.9

    var cornerRadius: CGFloat = 22
    /// How far along the tail-bearing edge the tail's base is centred, in
    /// points from the near corner — an absolute distance, not a fraction of
    /// the width. A fraction moved the tail into the middle of the bubble as it
    /// was widened, dragging the tip away from the character; a fixed distance
    /// leaves the tip where it is and grows the bubble out to the other side.
    var tailInset: CGFloat = 180
    var tailBaseWidth: CGFloat = 30
    var tailLength: CGFloat = Self.defaultTailLength * Self.tailLengthRatio
    /// How far the tip drifts sideways from the base, giving the long
    /// diagonal comic-tail slant that points toward the character (which the
    /// window layout aligns near the 0.22 width fraction).
    var tailDrift: CGFloat = 55
    var isMirrored: Bool = false
    var isFlippedVertically: Bool = false

    /// Where the tail tip lands, in points from the bubble's leading edge, for
    /// the un-mirrored shape. Window placement uses this to line the tip up with
    /// the character instead of duplicating the geometry as a magic number.
    /// Independent of the width, which is the point: resizing the bubble must
    /// not move the tip.
    static var tailTipOffset: CGFloat {
        let shape = SpeechBubbleShape()
        return max(shape.cornerRadius, shape.tailInset - shape.tailBaseWidth / 2) - shape.tailDrift
    }

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let tailCenterX = rect.minX + tailInset
        let tailBaseLeftX = max(rect.minX + r, tailCenterX - tailBaseWidth / 2)
        let tailBaseRightX = min(rect.maxX - r, tailCenterX + tailBaseWidth / 2)
        let tip = CGPoint(x: tailBaseLeftX - tailDrift, y: rect.maxY + tailLength)

        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: tailBaseRightX, y: rect.maxY))

        // Right side of the tail: gentle concave curve down to the tip.
        path.addCurve(
            to: tip,
            control1: CGPoint(x: tailBaseRightX - 4, y: rect.maxY + tailLength * 0.4),
            control2: CGPoint(x: tip.x + tailBaseWidth * 0.3, y: tip.y - tailLength * 0.15)
        )
        // Left side of the tail: smooth convex curve back up to the bubble.
        path.addCurve(
            to: CGPoint(x: tailBaseLeftX, y: rect.maxY),
            control1: CGPoint(x: tip.x - 3, y: tip.y + tailLength * 0.1),
            control2: CGPoint(x: tailBaseLeftX - tailBaseWidth * 0.2, y: rect.maxY + tailLength * 0.55)
        )

        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.closeSubpath()

        if isMirrored {
            let hFlip = CGAffineTransform(translationX: rect.midX, y: 0)
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -rect.midX, y: 0)
            path = path.applying(hFlip)
        }

        if isFlippedVertically {
            let vFlip = CGAffineTransform(translationX: 0, y: rect.midY)
                .scaledBy(x: 1, y: -1)
                .translatedBy(x: 0, y: -rect.midY)
            path = path.applying(vFlip)
        }

        return path
    }
}
