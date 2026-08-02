import SwiftUI
import AppKit

/// A message body, rendered by AppKit so its links actually behave like links.
///
/// SwiftUI's `Text` draws link attributes but doesn't act on them inside a
/// non-activating panel — the click falls through to whatever window is behind
/// the bubble, and the pointer never changes. `NSTextView` handles all three
/// things a link needs: it opens on click without stealing focus, it shows the
/// pointing-hand cursor, and it gives us somewhere to hang the hover underline.
/// Text selection comes along with it.
struct MessageTextView: NSViewRepresentable {
    let text: AttributedString
    let fontSize: Double

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
        // Underlining is left to hover, so the resting state stays quiet.
        view.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand
        ]
        return view
    }

    func updateNSView(_ view: HoverLinkTextView, context: Context) {
        let styled = Self.styled(text, fontSize: fontSize)
        if view.textStorage?.isEqual(to: styled) != true {
            view.textStorage?.setAttributedString(styled)
        }
    }

    /// SwiftUI needs a height for the width it's offering; ask the layout
    /// manager rather than guessing, or long replies get clipped.
    ///
    /// The width reported back is the width the text *used*, which is narrower
    /// than the offer for anything short. That is what lets a bubble hug a
    /// two-word message; returning the offered width made every bubble as wide
    /// as the row.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: HoverLinkTextView,
        context: Context
    ) -> CGSize? {
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else {
            return nil
        }
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0 else { return nil }

        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        // Rounded up, and never wider than the offer: `usedRect` can come back a
        // fraction over the container's own width, which would re-wrap the last
        // word on the next pass.
        return CGSize(width: min(width, ceil(used.width)), height: ceil(used.height))
    }

    /// The transcript is monospaced; markdown emphasis keeps that face and only
    /// changes weight/slant, so a bold word doesn't jump to a different font.
    static func styled(_ text: AttributedString, fontSize: Double) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let size = CGFloat(fontSize)
        let plain = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)

        let base: [NSAttributedString.Key: Any] = [
            .font: plain,
            .foregroundColor: NSColor.labelColor
        ]
        result.addAttributes(base, range: NSRange(location: 0, length: result.length))

        for run in text.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            let range = NSRange(run.range, in: text)
            if intent.contains(.stronglyEmphasized) {
                result.addAttribute(.font, value: bold, range: range)
            }
            if intent.contains(.emphasized) {
                let italic = NSFontManager.shared.convert(plain, toHaveTrait: .italicFontMask)
                result.addAttribute(.font, value: italic, range: range)
            }
        }

        // Link colour is applied by `linkTextAttributes`, but the foreground
        // pass above would otherwise have overwritten it in the storage.
        result.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: result.length)
        ) { value, range, _ in
            guard value != nil else { return }
            result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        }
        return result
    }
}

/// Underlines whichever link the pointer is over, and nothing else.
///
/// The underline is a temporary attribute rather than an edit to the text, so
/// hovering never touches the message itself.
final class HoverLinkTextView: NSTextView {
    private var hovered: NSRange?

    /// The panel doesn't take focus, so without this the first click on a link
    /// would only serve to activate the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                // `activeAlways`: the bubble floats over other apps, so the
                // pointer is often here while this app isn't the active one.
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

    /// Where AppKit actually decides which cursor to show. The `.cursor` link
    /// attribute isn't enough here: that runs off cursor rects, which are only
    /// maintained for the key window, and this panel never becomes key.
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
        // Past the end of a line the nearest glyph is still "hit"; the fraction
        // is what tells us the pointer is actually beyond it.
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
