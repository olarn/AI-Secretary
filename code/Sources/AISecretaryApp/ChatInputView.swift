import SwiftUI
import AppKit
import SecretaryCore

/// The message box: one line to begin with, growing a line at a time as the
/// message gets longer and scrolling once it reaches five.
///
/// AppKit rather than SwiftUI's `TextField(axis: .vertical)`, which looked right
/// but wasn't: in this panel Return gave up first-responder status instead of
/// sending, so there was no way to send a message from the keyboard, and the
/// wheel wouldn't scroll the overflow. Owning the text view means owning both.
struct ChatInputView: NSViewRepresentable {
    @Binding var text: String
    /// The same size the messages use: what's being typed is a message, and a
    /// box that stayed at caption size while the transcript grew to 32pt made
    /// the thing you were writing the hardest part to read.
    let fontSize: Double
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ChatInputTextView()
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.font = Self.font(fontSize)
        textView.isRichText = false
        textView.drawsBackground = false
        // Inset on both edges, not just the sides: with no vertical inset the
        // text sat against the top of the box while the box reserved room below
        // it, which read as the text floating rather than sitting in the field.
        textView.textContainerInset = CGSize(width: 4, height: Self.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        // Off by default for a one-line box; switched on in `updateNSView` once
        // the message outgrows five lines.
        scrollView.verticalScrollElasticity = .none
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ChatInputTextView else { return }
        context.coordinator.onSubmit = onSubmit
        // Only when it actually differs: assigning during editing would move the
        // caret to the end on every keystroke.
        if textView.string != text {
            textView.string = text
        }
        let font = Self.font(fontSize)
        if textView.font != font {
            textView.font = font
            // The text already in the box was laid out in the old size.
            textView.textStorage?.addAttribute(
                .font,
                value: font,
                range: NSRange(location: 0, length: textView.textStorage?.length ?? 0)
            )
            textView.needsDisplay = true
        }
        textView.placeholder = placeholder
        scrollView.verticalScrollElasticity = Self.scrolls(textView) ? .allowed : .none
    }

    /// The height SwiftUI should give the row — which is what makes the box grow
    /// a line at a time, and stop.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSScrollView,
        context: Context
    ) -> CGSize? {
        guard let textView = nsView.documentView as? ChatInputTextView else { return nil }
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0 else { return nil }

        return CGSize(width: width, height: Self.textHeight(textView, width: width) + Self.padding)
    }

    // MARK: - Measurement

    static func font(_ size: Double) -> NSFont { .systemFont(ofSize: size) }

    /// The box's own inset above and below the text.
    static let verticalInset: Double = 4
    private static var padding: Double { verticalInset * 2 }

    private static func lineHeight(_ textView: NSTextView) -> Double {
        let font = textView.font ?? Self.font(11)
        guard let manager = textView.layoutManager else { return Double(font.pointSize) }
        return Double(manager.defaultLineHeight(for: font))
    }

    private static func contentHeight(_ textView: NSTextView, width: Double) -> Double {
        guard let container = textView.textContainer, let manager = textView.layoutManager else {
            return lineHeight(textView)
        }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return Double(manager.usedRect(for: container).height)
    }

    private static func textHeight(_ textView: NSTextView, width: Double) -> Double {
        ChatInputMetrics.height(
            forContent: contentHeight(textView, width: width),
            lineHeight: lineHeight(textView)
        )
    }

    private static func scrolls(_ textView: NSTextView) -> Bool {
        ChatInputMetrics.scrolls(
            contentHeight: contentHeight(textView, width: Double(textView.bounds.width)),
            lineHeight: lineHeight(textView)
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        /// Return sends; Shift- or Option-Return breaks the line. Without this
        /// the field editor's own idea of Return wins, and in this panel that
        /// means quietly dropping first-responder status instead of sending.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            switch ChatInputMetrics.returnAction(
                shift: flags.contains(.shift),
                option: flags.contains(.option)
            ) {
            case .newline:
                textView.insertNewlineIgnoringFieldEditor(nil)
            case .send:
                onSubmit()
            }
            return true
        }
    }
}

/// Adds the two things `NSTextView` doesn't bring: placeholder text, and taking
/// the very first click in a panel that never becomes the active app.
final class ChatInputTextView: NSTextView {
    var placeholder: String = "" {
        didSet { if placeholder != oldValue { needsDisplay = true } }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? ChatInputView.font(11),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let origin = CGPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        placeholder.draw(at: origin, withAttributes: attributes)
    }

    /// Redrawn on every edit so the placeholder disappears with the first
    /// character and comes back when the box is emptied.
    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}
