import SwiftUI

struct SpeechBubbleShape: Shape {
    static let defaultTailLength: CGFloat = 30
    static let tailLengthRatio: CGFloat = 0.9

    var cornerRadius: CGFloat = 22
    var tailInset: CGFloat = 180
    var tailBaseWidth: CGFloat = 30
    var tailLength: CGFloat = Self.defaultTailLength * Self.tailLengthRatio
    var tailDrift: CGFloat = 55
    var isMirrored: Bool = false
    var isFlippedVertically: Bool = false

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

        path.addCurve(
            to: tip,
            control1: CGPoint(x: tailBaseRightX - 4, y: rect.maxY + tailLength * 0.4),
            control2: CGPoint(x: tip.x + tailBaseWidth * 0.3, y: tip.y - tailLength * 0.15)
        )
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
