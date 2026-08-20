import AppKit
import SwiftUI
import Observation
import SecretaryCore

/// Panes of the conversation that have been pulled out to stay on screen.
///
/// One floating window each, all of them independent of the chat: the point is
/// to keep a table in view while the conversation moves on, so closing the
/// bubble must not take them with it.
///
/// Nothing here throws a pane away except the user saying so. The close button
/// and Esc both only put a window away; the pane stays in the menu and comes
/// back from it. Losing pinned text to a stray click on a red dot was the wrong
/// trade — the whole point of pinning is that the text survives.
///
/// `Clear all`, and dropping the oldest past the limit, are the only ways a
/// pane is destroyed.
@MainActor
@Observable
final class InfoWindows: NSObject, NSWindowDelegate {
    /// What exists, whether or not it is on screen — a pane put away is still
    /// here, which is what the menu is built from.
    private(set) var set: InfoWindowSet = .empty

    @ObservationIgnored private var panels: [UUID: NSPanel] = [:]
    @ObservationIgnored private let appearance: Appearance
    /// Told whenever the number of panes *on screen* changes, so Esc is claimed
    /// while a pane is up even with the chat closed, and released the moment the
    /// last one is put away.
    ///
    /// Every hide and every show has to report, not just open and remove: a pane
    /// put away leaves the screen while staying in the set, and that is exactly
    /// the difference `hasSomethingToDismiss` was rewritten to notice. Firing
    /// only on the set's count is what left Esc claimed with an empty desktop.
    @ObservationIgnored var onVisibilityChanged: (() -> Void)?

    /// How many panes are actually on screen. The set's count answers a
    /// different question — see `hasSomethingToDismiss`.
    var visiblePaneCount: Int { panels.values.filter(\.isVisible).count }

    init(appearance: Appearance) {
        self.appearance = appearance
    }

    func applyControlAppearance(_ controls: NSAppearance?) {
        panels.values.forEach { paint($0, controls: controls) }
    }

    /// Everything about a pinned window that AppKit draws rather than SwiftUI.
    ///
    /// The owner (2026-08-20): a pinned window came up in the *system's* theme
    /// rather than the character's. Her palette was reaching the content —
    /// `InfoWindowView` sets it — so what was left showing was the window
    /// itself: the title bar, and the ground behind the hosting view. Those are
    /// AppKit's, and `appearance` alone was evidently not enough to move them.
    ///
    /// So the surface is painted from her palette outright, in her own sRGB
    /// values, and the title bar is made transparent so it takes that colour
    /// instead of drawing its own. Nothing here can resolve against the
    /// system's setting, because nothing here asks the system anything.
    private func paint(_ panel: NSPanel, controls: NSAppearance?) {
        // Still set: it decides the caret, the scroller and the title text,
        // which are drawn by AppKit and are not colours we can hand it.
        panel.appearance = controls

        guard appearance.settings.liquidGlass else {
            panel.titlebarAppearsTransparent = true
            panel.isOpaque = true
            panel.backgroundColor = appearance.colors.ground.nsColor
            panel.hasShadow = true
            panel.invalidateShadow()
            return
        }

        // Glass frosts what is *behind the window*, so an opaque window gives
        // it nothing to work with and the surface comes out a flat slab. The
        // ground colour painted above is exactly what has to go.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Left to AppKit here, deliberately, and it is the one place this
        // window differs from the bubble: a `.titled` window's bar is already a
        // translucent material lit by `panel.appearance`, which is hers.
        // Making it transparent instead would leave a strip of bare desktop
        // across the top, because the content view does not reach under the bar
        // without `.fullSizeContentView`.
        panel.titlebarAppearsTransparent = false
        // The same lesson as the chat bubble at 0.21.323: the window's own
        // shadow is invisible behind a solid ground and shows through a frosted
        // one as a dark smear. AppKit caches the shape, so switching it off is
        // not enough on its own.
        panel.hasShadow = false
        panel.invalidateShadow()
    }

    /// Also the door a ` ```window ` block in a reply comes through, so a pane
    /// the assistant asks for behaves exactly like one pinned by hand.
    func open(_ spec: InfoWindowSpec) {
        // Already pinned: bring that one forward rather than making a second
        // copy of it. See `InfoWindowSet.matching` for why this is on content
        // and not on a timer.
        if let existing = set.matching(title: spec.title, body: spec.body) {
            show(existing.id)
            return
        }
        // Dropping the oldest is the set's rule; its window has to go with it.
        let before = Set(set.windows.map(\.id))
        set = set.adding(spec)
        let after = Set(set.windows.map(\.id))
        for gone in before.subtracting(after) { destroyPanel(gone) }
        onVisibilityChanged?()
        show(spec.id)
    }

    func show(_ id: UUID) {
        guard let spec = set.window(id) else { return }
        NSApp.activate(ignoringOtherApps: true)
        // A pane coming back from the menu with the chat closed is the whole
        // reason this reports: it is the moment Esc has something to put away
        // again, and nothing else would say so.
        defer { onVisibilityChanged?() }

        if let panel = panels[id] {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingView(
            rootView: InfoWindowView(spec: spec, appearance: appearance)
        )
        // The rule is infoWindowSize, in SecretaryCore where it has tests.
        let frame = NSRect(origin: .zero, size: infoWindowSize(fitting: host.fittingSize))

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = spec.title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // What is on screen is this app's decision, not AppKit's saved state.
        panel.isRestorable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        paint(panel, controls: appearance.colors.controlAppearance)
        panel.contentView = host
        panel.setFrameTopLeftPoint(nextOrigin())
        panel.makeKeyAndOrderFront(nil)
        panels[id] = panel
    }

    /// Every pane back on screen, in the order they were pinned so the newest
    /// ends up in front.
    func showAll() {
        for spec in set.windows { show(spec.id) }
    }

    /// Esc: off the screen, still in the menu.
    func hide(_ id: UUID) {
        panels[id]?.orderOut(nil)
        onVisibilityChanged?()
    }

    /// ⌘H: all of them off the screen, all still in the menu. The counterpart
    /// of `showAll`.
    func hideAll() {
        panels.values.forEach { $0.orderOut(nil) }
        onVisibilityChanged?()
    }

    /// Whether one of these panes is the window being typed in — asked by the
    /// character who owns them, so Esc goes to her.
    func holds(_ window: NSWindow) -> Bool {
        panels.values.contains { $0 === window }
    }

    /// Hides whichever pane is being typed in, and says whether it did. The Esc
    /// ladder asks this first so that Esc means "put this away" when a pane has
    /// the keyboard, and "close the chat" otherwise.
    @discardableResult
    func hideKeyWindow() -> Bool {
        guard let key = NSApp.keyWindow,
              let id = panels.first(where: { $0.value === key })?.key
        else { return false }
        hide(id)
        return true
    }

    /// The frontmost pane that is on screen, put away, whether or not it holds
    /// the keyboard — and whether it did.
    ///
    /// The rung between `hideKeyWindow` and the chat. Esc is claimed from the
    /// whole system while a pane is up, so it arrives while the person is typing
    /// in another app entirely: no pane of ours holds the keyboard then, and
    /// without this the claim was spent on nothing while a pane sat there in
    /// plain sight refusing to go away.
    @discardableResult
    func hideFrontmostVisible() -> Bool {
        guard let id = panels
            .filter(\.value.isVisible)
            .min(by: { $0.value.orderedIndex < $1.value.orderedIndex })?
            .key
        else { return false }
        hide(id)
        return true
    }

    /// Explicit removal, from `Clear all` or from the limit being reached.
    func remove(_ id: UUID) {
        destroyPanel(id)
        set = set.removing(id)
        onVisibilityChanged?()
    }

    func clearAll() {
        for id in panels.keys { destroyPanel(id) }
        set = set.cleared
        onVisibilityChanged?()
    }

    private func destroyPanel(_ id: UUID) {
        guard let panel = panels.removeValue(forKey: id) else { return }
        panel.delegate = nil
        panel.orderOut(nil)
    }

    /// Cascade, so a second window doesn't land exactly on the first. The rule
    /// is infoWindowOrigin, in SecretaryCore where it has tests.
    private func nextOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 200, y: 600) }
        return infoWindowOrigin(visibleFrame: screen.visibleFrame, existingWindows: panels.count)
    }

    // MARK: - NSWindowDelegate

    /// The window's own close button, which puts the pane away without
    /// destroying it — the same thing Esc does. It stays in the status bar menu
    /// and one click brings it back, text and all.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let id = panels.first(where: { $0.value === sender })?.key else { return true }
        hide(id)
        return false
    }
}

/// One pane's contents: the same renderer the chat uses, scrolled.
private struct InfoWindowView: View {
    /// This window sets the palette rather than inheriting one: it is a root,
    /// not a view inside the chat panel.
    private var theme: Palette { appearance.colors }

    let spec: InfoWindowSpec
    let appearance: Appearance

    @State private var copied = false
    @State private var hovering = false

    /// The pane's ground: Liquid Glass when the character has switched it on,
    /// otherwise her solid ground — the same rule, and the same shape of code,
    /// as the chat bubble's `bubbleSurface`.
    @ViewBuilder
    private var surface: some View {
        if appearance.settings.liquidGlass {
            ZStack {
                // Not decoration. A window is click-through wherever its pixels
                // are fully transparent, and `Color.clear` under a
                // `glassEffect` counts as transparent however frosted it looks
                // — that is what killed the chat bubble's resize grip at
                // 0.21.322. 0.15 is above the window server's ~5% threshold and
                // invisible under the frosting. Do not "clean this up" into
                // `Color.clear`.
                Rectangle().fill(theme.ground.color(opacity: 0.15))
                Color.clear.glassEffect(.regular, in: Rectangle())
            }
        } else {
            theme.ground.color
        }
    }

    var body: some View {
        ScrollView {
            MarkdownBodyView(
                text: spec.body,
                fontSize: appearance.settings.fontSize,
                font: appearance.settings.font,
                secondaryFontSize: appearance.settings.secondaryFontSize
            )
            .padding(16)
        }
        .frame(minWidth: 300, minHeight: 160)
        // Only while the pointer is on the window, the same rule as in the
        // chat: a pane is pinned to be looked at, and a button sitting on it
        // permanently is in the way of the one thing it holds.
        .overlay(alignment: .topTrailing) {
            if hovering { copyButton }
        }
        .onHover { hovering = $0 }
        // `themedWindow` is deliberately taken apart here. Its `.background`
        // is a solid ground, and a solid ground behind glass is the one thing
        // glass must not have — it would frost that instead of the desktop and
        // come out flat. Everything else it does is wanted.
        .background(surface)
        .environment(\.palette, theme)
        .foregroundStyle(theme.primaryText.color)
        .tint(theme.accent.color)
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(spec.body, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: appearance.settings.secondaryFontSize))
                .foregroundStyle(theme.mutedText.color)
                .padding(5)
                .background(theme.chipFill.color, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Copy this window's text")
        .padding(8)
    }
}
