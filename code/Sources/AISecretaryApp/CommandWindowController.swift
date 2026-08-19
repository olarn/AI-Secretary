import AppKit
import SwiftUI
import SecretaryCore

/// The command window's panel: a `FloatingPanel` that can also be resized by
/// its edges. `.resizable` in the style mask is not enough — a *borderless*
/// window gets no resize bands from AppKit at all (driven 2026-08-19: drags
/// on and just outside every edge either moved the window or did nothing).
/// So the edges are tracked by hand, in `sendEvent`, which is also what keeps
/// it smooth: the frame moves synchronously with each dragged event instead
/// of round-tripping through a SwiftUI gesture.
private final class ResizablePanel: FloatingPanel {
    /// How far from an edge still counts as grabbing it.
    private let band: CGFloat = 6
    /// True while the person is holding an edge. The content-height follow
    /// must not re-anchor the frame during that — two writers re-anchoring
    /// against each other walked the window down the screen by exactly the
    /// resize amount (driven 2026-08-19).
    private(set) var isUserResizing = false

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            // An event that arrives while this window is not key carries no
            // window, and `locationInWindow` is then screen coordinates — the
            // edge test read those against the window's size and never
            // matched (driven 2026-08-19: the same grab resized when the
            // window was key and moved it when it was not).
            let p = event.window == nil
                ? convertPoint(fromScreen: event.locationInWindow)
                : event.locationInWindow
            let f = frame
            let edges = (
                l: p.x < band,
                r: p.x > f.width - band,
                t: p.y > f.height - band,
                b: p.y < band
            )
            if edges.l || edges.r || edges.t || edges.b {
                track(edges, from: f, mouse: NSEvent.mouseLocation)
                return
            }
        }
        super.sendEvent(event)
    }

    /// A synchronous tracking loop, not passive event watching: a swallowed
    /// mouseDown starts no AppKit drag session, so the dragged events that
    /// follow it are never routed back to this window (driven 2026-08-19 —
    /// the grab armed and then nothing arrived). Pulling them with
    /// `nextEvent` is the pattern every borderless window resize uses.
    private func track(
        _ edges: (l: Bool, r: Bool, t: Bool, b: Bool),
        from start: NSRect,
        mouse: NSPoint
    ) {
        isUserResizing = true
        defer { isUserResizing = false }
        while let event = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp { return }
            apply((edges, start, mouse), mouse: NSEvent.mouseLocation)
        }
    }

    private func apply(
        _ r: (edges: (l: Bool, r: Bool, t: Bool, b: Bool), frame: NSRect, mouse: NSPoint),
        mouse: NSPoint
    ) {
        let dx = mouse.x - r.mouse.x
        let dy = mouse.y - r.mouse.y
        var f = r.frame
        if r.edges.r { f.size.width = r.frame.width + dx }
        if r.edges.l {
            f.size.width = r.frame.width - dx
            f.origin.x = r.frame.maxX - f.width
        }
        // The top edge is the one that grows upward; every other change keeps
        // the top still, matching how the content-height follow behaves.
        if r.edges.t { f.size.height = r.frame.height + dy }
        if r.edges.b {
            f.size.height = r.frame.height - dy
            f.origin.y = r.frame.maxY - f.height
        }
        f.size.width = min(max(f.width, contentMinSize.width), contentMaxSize.width)
        let clampedHeight = min(max(f.height, contentMinSize.height), contentMaxSize.height)
        if r.edges.b { f.origin.y = r.frame.maxY - clampedHeight }
        f.size.height = clampedHeight
        if r.edges.l { f.origin.x = r.frame.maxX - f.width }
        setFrame(f, display: true)
    }
}

/// The one command window: a borderless floating slab, remembered where it was
/// left, hidden — never torn down — by Esc and the menu row.
///
/// Belongs to the app, not to a character, so like Token Usage it borrows the
/// focused character's look and has to notice when that character changes.
@MainActor
final class CommandWindowController {
    private let model: CommandCenter
    private var panel: FloatingPanel?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    /// The ↑↓ recall monitor — see `watchArrowKeys`.
    private var arrowKeyMonitor: Any?
    /// The slab's height with no granted extra — what the window may never
    /// shrink below, and the zero point the extra is measured from.
    private var naturalHeight: Double = 0
    /// Whose look the contents were built from — the same staleness check as
    /// `UsageWindow.follow`, for the same reason.
    private var builtFor: ObjectIdentifier?

    init(model: CommandCenter) {
        self.model = model
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    /// Whether Esc typed here is this window's to answer.
    var isKey: Bool { panel?.isKeyWindow ?? false }

    func toggle(using appearance: Appearance) {
        if isVisible { hide() } else { show(using: appearance) }
    }

    func show(using appearance: Appearance) {
        let panel = builtPanel(using: appearance)
        model.slabWidth = commandWindowWidth(
            saved: UserDefaults.standard.object(forKey: commandWindowWidthKey) as? Double
        )
        model.extraBoxHeight = max(0, UserDefaults.standard.double(forKey: commandWindowExtraHeightKey))
        panel.setContentSize(CGSize(width: model.slabWidth, height: panel.frame.height))
        panel.setFrameOrigin(commandWindowOrigin(
            saved: UserDefaults.standard.string(forKey: commandWindowOriginKey),
            size: panel.frame.size,
            visibleFrame: (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        ))
        // Nothing in this app takes focus by itself; without activating, the
        // window opens behind whatever is in front and reads as "nothing
        // happened" — and the whole point of opening it is to type.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusRequests += 1
    }

    /// Esc and the menu row: off the screen, sessions untouched. What was
    /// ticked, the files waiting, and who has been commanded all survive.
    func hide() {
        panel?.orderOut(nil)
    }

    private func builtPanel(using appearance: Appearance) -> FloatingPanel {
        if let panel {
            follow(appearance)
            return panel
        }

        let host = FirstMouseHostingView(rootView: builtView(using: appearance))
        // The window is sized by this controller alone, from the slab-height
        // preference. Left at its default, the hosting view re-fits the
        // window to the content after every edge-resize — the person drags
        // the bottom edge down and the window snaps back up (driven
        // 2026-08-19, a 53pt resize that ended as a 53pt slide instead).
        host.sizingOptions = []

        let panel = ResizablePanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: commandWindowDefaultWidth, height: 160)),
            content: host,
            // Typing is what this window is for; a click anywhere in it should
            // hand over the keyboard, same as the chat.
            takesKeyOnClick: true
        )
        panel.appearance = appearance.colors.controlAppearance
        // Off, deliberately, though every other FloatingPanel has it on: the
        // window server honours it *beside* our own edge tracking and the
        // performDrag move, and the two moved the window a second time after
        // every resize (driven 2026-08-19 — each grow slid the window by the
        // same distance). All dragging goes through the SwiftUI gesture.
        panel.isMovableByWindowBackground = false
        self.panel = panel
        builtFor = ObjectIdentifier(appearance)

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followUserResize() }
        }
        watchArrowKeys()
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(
                    commandWindowOriginString(panel.frame.origin),
                    forKey: commandWindowOriginKey
                )
            }
        }
        return panel
    }

    /// ↑↓ recall what this box has sent, exactly as the chat box does — and
    /// through the same door: a local `NSEvent` monitor, because `TextField`
    /// eats the arrow keys before `.onKeyPress` ever sees them (the chat's
    /// receipt for this is in `ChatPanelView+Keys`). Who owns the arrows is
    /// `ArrowKeyOwner`'s decision, not an `if` chain here: a multi-line draft
    /// keeps them for the caret. No choices are passed — the results strip's
    /// picker is clicked, not steered, so the arrows never mean three things
    /// in this window.
    private func watchArrowKeys() {
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel, panel.isKeyWindow else { return event }
            guard event.keyCode == 126 || event.keyCode == 125 else { return event }
            guard ArrowKeyOwner.owner(
                hasChoices: false,
                draft: model.draft,
                hasHistory: model.hasRecallHistory
            ) == .history else { return event }
            let handled = event.keyCode == 126 ? model.recallOlder() : model.recallNewer()
            return handled ? nil : event
        }
    }

    /// The view, wired back to the window it lives in for the background drag
    /// — the gesture and the reason it exists are `CommandWindowView`'s.
    private func builtView(using appearance: Appearance) -> CommandWindowView {
        CommandWindowView(
            model: model,
            appearance: appearance,
            beginWindowDrag: { [weak self] in
                guard let panel = self?.panel, let event = NSApp.currentEvent else { return }
                panel.performDrag(with: event)
            },
            hideWindow: { [weak self] in self?.hide() },
            contentHeightChanged: { [weak self] height in self?.followContentHeight(height) }
        )
    }

    /// The person dragged an edge. Width is taken as it is (clamped);
    /// anything above the natural height becomes the box's granted extra —
    /// the owner's rule: a taller window is a taller text box, everything
    /// else keeps its place. Both are remembered, like the origin.
    private func followUserResize() {
        guard let panel, naturalHeight > 0 else { return }
        let width = commandWindowWidth(saved: panel.frame.width)
        if abs(width - model.slabWidth) > 0.5 {
            model.slabWidth = width
            UserDefaults.standard.set(width, forKey: commandWindowWidthKey)
        }
        let extra = max(0, panel.frame.height - naturalHeight)
        if abs(extra - model.extraBoxHeight) > 0.5 {
            model.extraBoxHeight = extra
            UserDefaults.standard.set(extra, forKey: commandWindowExtraHeightKey)
        }
    }

    /// The window's height follows the slab — the box grows to ten lines,
    /// files and the error line come and go — with the *top* edge held still,
    /// because AppKit grows a frame upward and a window that jumps up when an
    /// error line appears reads as broken. Not `sizingOptions`: see the
    /// warning on `contentHeightChanged` in the view.
    ///
    /// `height` arrives as natural height plus the granted extra, because the
    /// box already draws the extra; the minimum the window may shrink to is
    /// the natural part alone.
    private func followContentHeight(_ height: Double) {
        guard let panel, height > 0 else { return }
        naturalHeight = max(1, height - model.extraBoxHeight)
        panel.contentMinSize = CGSize(width: 380, height: naturalHeight)
        panel.contentMaxSize = CGSize(width: 1000, height: 10_000)
        // While an edge is held, the person's hand owns the frame — the
        // resize loop is already applying it, and a second writer here
        // re-anchors against a frame mid-change and walks the window.
        guard (panel as? ResizablePanel)?.isUserResizing != true else { return }
        guard abs(panel.frame.height - height) > 0.5 else { return }
        let top = panel.frame.maxY
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: top - height, width: panel.frame.width, height: height),
            display: true
        )
    }

    /// Puts this window in one character's look — appearance and contents move
    /// together or the window wears half of each (see `UsageWindow.follow`).
    private func follow(_ appearance: Appearance) {
        guard let panel else { return }
        panel.appearance = appearance.colors.controlAppearance
        guard builtFor != ObjectIdentifier(appearance) else { return }
        let host = FirstMouseHostingView(rootView: builtView(using: appearance))
        host.sizingOptions = []
        panel.contentView = host
        builtFor = ObjectIdentifier(appearance)
    }
}
