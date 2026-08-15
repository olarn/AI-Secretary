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
    /// Told when the set becomes empty or non-empty, so Esc is claimed while a
    /// pane is up even with the chat closed, and released when the last one goes.
    @ObservationIgnored var onCountChanged: (() -> Void)?

    init(appearance: Appearance) {
        self.appearance = appearance
    }

    func applyControlAppearance(_ controls: NSAppearance?) {
        panels.values.forEach { $0.appearance = controls }
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
        panel.appearance = appearance.colors.controlAppearance
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

    /// ⌘H: all of them off the screen, all still in the menu. The counterpart
    /// of `showAll`.
    func hideAll() {
        panels.values.forEach { $0.orderOut(nil) }
    }

    /// Hides whichever pane is frontmost, and says whether it did. The Esc hot
    /// key asks this first so that Esc means "put this away" when a pane is in
    /// front, and "close the chat" otherwise.
    @discardableResult
    /// Whether one of these panes is the window being typed in — asked by the
    /// character who owns them, so Esc goes to her.
    func holds(_ window: NSWindow) -> Bool {
        panels.values.contains { $0 === window }
    }

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
        .themedWindow(theme)
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
