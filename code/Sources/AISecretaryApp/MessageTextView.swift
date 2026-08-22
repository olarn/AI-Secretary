import SwiftUI
import SecretaryCore
import AppKit

struct MessageTextView: NSViewRepresentable {
    let text: AttributedString
    let fontSize: Double
    let font: FontChoice
    let palette: Palette

    private static let unboundedWidth: CGFloat = 100_000

    func makeNSView(context: Context) -> HoverLinkTextView {
        let view = HoverLinkTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.linkTextAttributes = [
            .foregroundColor: palette.accent.nsColor,
            .cursor: NSCursor.pointingHand
        ]
        return view
    }

    func updateNSView(_ view: HoverLinkTextView, context: Context) {
        view.linkTextAttributes = [
            .foregroundColor: palette.accent.nsColor,
            .cursor: NSCursor.pointingHand
        ]
        let styled = Self.styled(text, fontSize: fontSize, font: font, palette: palette)
        if view.textStorage?.isEqual(to: styled) != true {
            view.textStorage?.setAttributedString(styled)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: HoverLinkTextView,
        context: Context
    ) -> CGSize? {
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else {
            return nil
        }
        let measured: CGFloat
        switch proposal.width {
        case .some(let width) where width > 0 && width.isFinite:
            measured = width
        case .some(let width) where width <= 0:
            measured = 1
        default:
            measured = Self.unboundedWidth
        }

        container.containerSize = CGSize(width: measured, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        return CGSize(width: min(measured, ceil(used.width)), height: ceil(used.height))
    }

    static func naturalWidth(_ text: AttributedString, fontSize: Double, font: FontChoice) -> Double {
        let styled = Self.styled(text, fontSize: fontSize, font: font, palette: .dark)
        return ceil(
            styled.boundingRect(
                with: CGSize(width: unboundedWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).width
        )
    }

    static func styled(
        _ text: AttributedString,
        fontSize: Double,
        font: FontChoice,
        palette: Palette
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let size = CGFloat(fontSize)
        let plain = Self.face(font, size: size, weight: .regular)
        let bold = Self.face(font, size: size, weight: .bold)

        let base: [NSAttributedString.Key: Any] = [
            .font: plain,
            .foregroundColor: palette.primaryText.nsColor
        ]
        result.addAttributes(base, range: NSRange(location: 0, length: result.length))

        for run in text.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            let strong = intent.contains(.stronglyEmphasized)
            let slanted = intent.contains(.emphasized)
            guard strong || slanted else { continue }
            let weighted = strong ? bold : plain
            let face = slanted
                ? NSFontManager.shared.convert(weighted, toHaveTrait: .italicFontMask)
                : weighted
            result.addAttribute(.font, value: face, range: NSRange(run.range, in: text))
        }

        result.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: result.length)
        ) { value, range, _ in
            guard value != nil else { return }
            result.addAttribute(.foregroundColor, value: palette.accent.nsColor, range: range)
        }
        return result
    }

    static func face(_ choice: FontChoice, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(choice.systemDesign),
              let face = NSFont(descriptor: descriptor, size: size)
        else { return system }
        return face
    }
}

extension FontChoice {
    var systemDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }

    var swiftUIDesign: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

final class HoverLinkTextView: NSTextView {
    private var hovered: NSRange?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let range = linkRange(at: convert(event.locationInWindow, from: nil))
        highlight(range)
        setCursor(overLink: range != nil)
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setCursor(overLink: linkRange(at: point) != nil)
    }

    private func setCursor(overLink: Bool) {
        (overLink ? NSCursor.pointingHand : NSCursor.iBeam).set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        highlight(nil)
        NSCursor.arrow.set()
    }

    private func linkRange(at point: CGPoint) -> NSRange? {
        guard let manager = layoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0
        else { return nil }

        var fraction: CGFloat = 0
        let glyph = manager.glyphIndex(
            for: point,
            in: container,
            fractionOfDistanceThroughGlyph: &fraction
        )
        guard fraction < 1 else { return nil }

        let character = manager.characterIndexForGlyph(at: glyph)
        guard character < storage.length else { return nil }

        var range = NSRange(location: 0, length: 0)
        guard storage.attribute(.link, at: character, effectiveRange: &range) != nil else {
            return nil
        }
        return range
    }

    private func highlight(_ range: NSRange?) {
        guard range != hovered else { return }
        if let hovered {
            layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: hovered)
        }
        if let range {
            layoutManager?.addTemporaryAttributes(
                [.underlineStyle: NSUnderlineStyle.single.rawValue],
                forCharacterRange: range
            )
        }
        hovered = range
    }
}
