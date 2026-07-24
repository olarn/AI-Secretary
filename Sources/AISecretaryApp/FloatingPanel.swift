import AppKit

/// A transparent, floating, non-activating panel used for both the desktop
/// character and its chat panel. Stays above normal windows without stealing
/// focus from the frontmost app, and can be dragged by its background.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect, content: NSView) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
