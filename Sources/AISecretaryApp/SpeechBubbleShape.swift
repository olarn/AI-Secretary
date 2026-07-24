import SwiftUI

/// A comic/manga-style speech bubble: a single continuous outline — rounded
/// rectangle body plus a curved, tapered tail on the bottom edge — so the
/// tail reads as part of the bubble rather than a shape pasted on top.
///
/// `isMirrored` flips the whole shape horizontally so the tail can switch
/// from the left side to the right side (and back) as the bubble is
/// repositioned to stay on-screen, while always aligning with the character.
struct SpeechBubbleShape: Shape {
    var cornerRadius: CGFloat = 22
    /// Fraction of the bottom edge (0 = left) where the tail's base is centered, before mirroring.
    var tailHorizontalPosition: CGFloat = 0.22
    var tailBaseWidth: CGFloat = 46
    var tailLength: CGFloat = 34
    /// How far the tip drifts left of the base center, for the classic diagonal comic tail.
    var tailDrift: CGFloat = 22
    var isMirrored: Bool = false

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let tailCenterX = rect.minX + rect.width * tailHorizontalPosition
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
            control1: CGPoint(x: tailBaseRightX - 6, y: rect.maxY + tailLength * 0.35),
            control2: CGPoint(x: tip.x + tailBaseWidth * 0.35, y: tip.y - tailLength * 0.2)
        )
        // Left side of the tail: smooth convex curve back up to the bubble.
        path.addCurve(
            to: CGPoint(x: tailBaseLeftX, y: rect.maxY),
            control1: CGPoint(x: tip.x - 4, y: tip.y + tailLength * 0.15),
            control2: CGPoint(x: tailBaseLeftX - tailBaseWidth * 0.25, y: rect.maxY + tailLength * 0.5)
        )

        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.closeSubpath()

        guard isMirrored else { return path }

        let flip = CGAffineTransform(translationX: rect.midX, y: 0)
            .scaledBy(x: -1, y: 1)
            .translatedBy(x: -rect.midX, y: 0)
        return path.applying(flip)
    }
}
