import AppKit
import SwiftUI

/// A plain container that also acts on the first click, for the cases where
/// AppKit hit-tests it rather than the SwiftUI view inside it.
final class FirstMouseContainerView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A SwiftUI host that acts on the very first click.
///
/// These panels deliberately never become the active app, so by default AppKit
/// treats a click on them as "bring this window forward" and swallows it. That
/// cost a click everywhere: opening the chat from the character took two, a
/// button in the panel took two, and a link took two.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

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
        // Without this the window is never told the pointer moved, so hover
        // effects inside it (the link underline and pointer) never fire.
        acceptsMouseMovedEvents = true
        // Don't take key status just because someone clicked: otherwise the
        // first click on the character only focuses the window and is thrown
        // away, and opening then closing the chat costs three clicks instead of
        // two. Controls that genuinely need focus — the text field — still get
        // it, because AppKit asks the view first.
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // The app decides what is on screen, not AppKit's saved state. Left
        // restorable, a panel hidden when the app was last quit can be ordered
        // out again after launch — undoing the `orderFrontRegardless` in
        // `applicationDidFinishLaunching` and leaving a running app with no way
        // to reach it except the status bar.
        isRestorable = false
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
