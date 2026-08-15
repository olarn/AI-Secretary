import SwiftUI
import SecretaryCore
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
    /// Which face the conversation is set in. Passed alongside the size for the
    /// same reason the size is passed at all: this is AppKit, so it needs a
    /// concrete `NSFont` at the moment the storage is built, not a SwiftUI
    /// modifier applied to it afterwards.
    let font: FontChoice
    /// Passed in rather than read from the environment: the text is drawn by
    /// AppKit into an `NSTextStorage`, so it needs `NSColor` values at the
    /// moment the storage is built — `labelColor` and `linkColor` follow the
    /// *system's* light/dark setting, which is not ours to assume.
    let palette: Palette

    /// Stands in for "as much room as you like" when measuring. A finite number
    /// rather than `.greatestFiniteMagnitude`: TextKit lays out against this
    /// value, and the infinities produce degenerate line fragments.
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
        // Underlining is left to hover, so the resting state stays quiet.
        view.linkTextAttributes = [
            .foregroundColor: palette.accent.nsColor,
            .cursor: NSCursor.pointingHand
        ]
        return view
    }

    func updateNSView(_ view: HoverLinkTextView, context: Context) {
        // Re-applied on every update, not only in `makeNSView`: the theme can
        // change while the window is open, and the link colour lives on the
        // view rather than in the storage.
        view.linkTextAttributes = [
            .foregroundColor: palette.accent.nsColor,
            .cursor: NSCursor.pointingHand
        ]
        let styled = Self.styled(text, fontSize: fontSize, font: font, palette: palette)
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
        // Every proposal is answered, including the two SwiftUI uses to learn
        // how flexible this view is. Returning nil for those — which is what
        // the zero-width and unspecified cases used to do — leaves the layout
        // treating the text as infinitely stretchy, and inside a bubble that
        // showed up as a two-word message filling the whole row.
        //
        // Answered properly, the range is: at its narrowest, the longest single
        // word; at its widest, the text set on one line.
        let measured: CGFloat
        switch proposal.width {
        case .some(let width) where width > 0 && width.isFinite:
            measured = width
        case .some(let width) where width <= 0:
            // A container of 1pt can't break a word, so what comes back is the
            // width of the longest one — the narrowest this text can ever be.
            measured = 1
        default:
            measured = Self.unboundedWidth
        }

        container.containerSize = CGSize(width: measured, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        // Rounded up, and never wider than the offer: `usedRect` can come back a
        // fraction over the container's own width, which would re-wrap the last
        // word on the next pass.
        return CGSize(width: min(measured, ceil(used.width)), height: ceil(used.height))
    }

    /// The width this text would take if nothing made it wrap.
    ///
    /// Used as a cap on the view, not as its size: a short message is held to
    /// its own width so the bubble hugs it, and a long one asks for more than
    /// the row has and gets the row. Measuring here rather than leaving it to
    /// `sizeThatFits` is deliberate — a representable is treated as fully
    /// stretchy by the surrounding layout no matter what it answers, which is
    /// why "ok?" was drawn in a bubble the full width of the panel.
    ///
    /// Measured in one pass, deliberately. A reply with newlines in it should be
    /// as wide as its widest line — which is what this returns, because a hard
    /// newline still breaks the line when nothing else does. Splitting the text
    /// up and measuring each line separately gives the same answer and costs a
    /// scan of the whole message per line, on every streamed token.
    ///
    /// Measured with a fixed palette, which is not a shortcut: colour has no
    /// effect on line breaking or on the width of a glyph, and threading the
    /// live theme through a pure measurement would suggest it did.
    static func naturalWidth(_ text: AttributedString, fontSize: Double, font: FontChoice) -> Double {
        let styled = Self.styled(text, fontSize: fontSize, font: font, palette: .dark)
        return ceil(
            styled.boundingRect(
                with: CGSize(width: unboundedWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).width
        )
    }

    /// Markdown emphasis keeps the chosen face and only changes weight and
    /// slant, so a bold word doesn't jump to a different font.
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

        // Weight and slant resolved together, in one write per run. They used to
        // be two independent `if`s writing the whole font each time, and the
        // second overwrote the first: `***bold italic***` carries both intents,
        // so it came out italic and lost its weight entirely.
        for run in text.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            let strong = intent.contains(.stronglyEmphasized)
            let slanted = intent.contains(.emphasized)
            guard strong || slanted else { continue }
            let weighted = strong ? bold : plain
            // A family with no italic face is left upright rather than faked —
            // `convert(_:toHaveTrait:)` hands back the font unchanged, which is
            // the honest outcome.
            let face = slanted
                ? NSFontManager.shared.convert(weighted, toHaveTrait: .italicFontMask)
                : weighted
            result.addAttribute(.font, value: face, range: NSRange(run.range, in: text))
        }

        // Link colour is applied by `linkTextAttributes`, but the foreground
        // pass above would otherwise have overwritten it in the storage.
        result.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: result.length)
        ) { value, range, _ in
            guard value != nil else { return }
            result.addAttribute(.foregroundColor, value: palette.accent.nsColor, range: range)
        }
        return result
    }

    /// The `NSFont` for a choice, built from the system face rather than from a
    /// family name.
    ///
    /// This is the whole reason the setting exists. The transcript used to ask
    /// for `monospacedSystemFont`, and SF Mono has no Thai glyphs, so every Thai
    /// word fell out of it into whatever the system reached for next — Ayuthaya,
    /// measured on 2026-08-14, which is wide and heavy enough that it was
    /// reported as the chat being bold. Nothing was bold. A design asked for
    /// this way is resolved per script, so each language gets that design's own
    /// face instead of a fallback nobody chose.
    ///
    /// Falls back to the plain system font at every step: an unavailable design
    /// should cost the shape, never the text.
    static func face(_ choice: FontChoice, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(choice.systemDesign),
              let face = NSFont(descriptor: descriptor, size: size)
        else { return system }
        return face
    }
}

extension FontChoice {
    /// Kept out of `SecretaryCore`, where the type lives: the enum is the
    /// choice, and this is AppKit's name for it.
    var systemDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }

    /// The same choice for the parts of a message SwiftUI draws itself — table
    /// cells, and the options under a question. They are the conversation too,
    /// and a table set in a different face from the paragraph above it reads as
    /// a rendering bug.
    var swiftUIDesign: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
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
