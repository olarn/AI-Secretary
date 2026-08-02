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
    /// What exists, whether or not it is on screen. The menu is built from this.
    private(set) var set: InfoWindowSet = .empty

    @ObservationIgnored private var panels: [UUID: NSPanel] = [:]
    @ObservationIgnored private let appearance: Appearance
    /// Told when the set becomes empty or non-empty, so Esc is claimed while a
    /// pane is up even with the chat closed, and released when the last one goes.
    @ObservationIgnored var onCountChanged: (() -> Void)?

    init(appearance: Appearance) {
        self.appearance = appearance
    }

    /// Opens a pane and shows it. Called when a reply carried a ` ```window `
    /// block.
    func open(_ spec: InfoWindowSpec) {
        // Dropping the oldest is the set's rule; its window has to go with it.
        let before = Set(set.windows.map(\.id))
        set = set.adding(spec)
        let after = Set(set.windows.map(\.id))
        for gone in before.subtracting(after) { destroyPanel(gone) }
        onCountChanged?()
        show(spec.id)
    }

    func show(_ id: UUID) {
        guard let spec = set.window(id) else { return }
        NSApp.activate(ignoringOtherApps: true)

        if let panel = panels[id] {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingView(
            rootView: InfoWindowView(spec: spec, appearance: appearance)
        )
        // Sized to the content, within reason: a two-row table should not open a
        // window the height of the screen, and a long one should not try to.
        let wanted = host.fittingSize
        let frame = NSRect(
            x: 0, y: 0,
            width: min(max(wanted.width + 32, 320), 720),
            height: min(max(wanted.height + 32, 180), 640)
        )

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
    }

    /// Hides whichever pane is frontmost, and says whether it did. The Esc hot
    /// key asks this first so that Esc means "put this away" when a pane is in
    /// front, and "close the chat" otherwise.
    @discardableResult
    func hideKeyWindow() -> Bool {
        guard let key = NSApp.keyWindow,
              let id = panels.first(where: { $0.value === key })?.key
        else { return false }
        hide(id)
        return true
    }

    /// Explicit removal, from `Clear all` or from the limit being reached.
    func remove(_ id: UUID) {
        destroyPanel(id)
        set = set.removing(id)
        onCountChanged?()
    }

    func clearAll() {
        for id in panels.keys { destroyPanel(id) }
        set = set.cleared
        onCountChanged?()
    }

    private func destroyPanel(_ id: UUID) {
        guard let panel = panels.removeValue(forKey: id) else { return }
        panel.delegate = nil
        panel.orderOut(nil)
    }

    /// Cascade, so a second window doesn't land exactly on the first.
    private func nextOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 200, y: 600) }
        let step = 26.0 * Double(panels.count % 8)
        return NSPoint(
            x: screen.visibleFrame.minX + 120 + step,
            y: screen.visibleFrame.maxY - 80 - step
        )
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
    let spec: InfoWindowSpec
    let appearance: Appearance

    var body: some View {
        ScrollView {
            MarkdownBodyView(
                text: spec.body,
                fontSize: appearance.settings.fontSize,
                secondaryFontSize: appearance.settings.secondaryFontSize
            )
            .padding(16)
        }
        .frame(minWidth: 300, minHeight: 160)
    }
}
