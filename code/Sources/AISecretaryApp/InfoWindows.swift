import AppKit
import SwiftUI
import Observation
import SecretaryCore

@MainActor
@Observable
final class InfoWindows: NSObject, NSWindowDelegate {
    private(set) var set: InfoWindowSet = .empty

    @ObservationIgnored private var panels: [UUID: NSPanel] = [:]
    @ObservationIgnored private let appearance: Appearance
    @ObservationIgnored var onVisibilityChanged: (() -> Void)?

    var visiblePaneCount: Int { panels.values.filter(\.isVisible).count }

    init(appearance: Appearance) {
        self.appearance = appearance
    }

    func applyControlAppearance(_ controls: NSAppearance?) {
        panels.values.forEach { paint($0, controls: controls) }
    }

    private func paint(_ panel: NSPanel, controls: NSAppearance?) {
        panel.appearance = controls

        guard appearance.settings.liquidGlass else {
            panel.titlebarAppearsTransparent = true
            panel.isOpaque = true
            panel.backgroundColor = appearance.colors.ground.nsColor
            panel.hasShadow = true
            panel.invalidateShadow()
            return
        }

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = false
        panel.hasShadow = false
        panel.invalidateShadow()
    }

    func open(_ spec: InfoWindowSpec) {
        if let existing = set.matching(title: spec.title, body: spec.body) {
            show(existing.id)
            return
        }
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
        defer { onVisibilityChanged?() }

        if let panel = panels[id] {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingView(
            rootView: InfoWindowView(spec: spec, appearance: appearance)
        )
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
        panel.isRestorable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        paint(panel, controls: appearance.colors.controlAppearance)
        panel.contentView = host
        panel.setFrameTopLeftPoint(nextOrigin())
        panel.makeKeyAndOrderFront(nil)
        panels[id] = panel
    }

    func showAll() {
        for spec in set.windows { show(spec.id) }
    }

    func hide(_ id: UUID) {
        panels[id]?.orderOut(nil)
        onVisibilityChanged?()
    }

    func hideAll() {
        panels.values.forEach { $0.orderOut(nil) }
        onVisibilityChanged?()
    }

    func holds(_ window: NSWindow) -> Bool {
        panels.values.contains { $0 === window }
    }

    @discardableResult
    func hideKeyWindow() -> Bool {
        guard let key = NSApp.keyWindow,
              let id = panels.first(where: { $0.value === key })?.key
        else { return false }
        hide(id)
        return true
    }

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

    private func nextOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 200, y: 600) }
        return infoWindowOrigin(visibleFrame: screen.visibleFrame, existingWindows: panels.count)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let id = panels.first(where: { $0.value === sender })?.key else { return true }
        hide(id)
        return false
    }
}

private struct InfoWindowView: View {
    private var theme: Palette { appearance.colors }

    let spec: InfoWindowSpec
    let appearance: Appearance

    @State private var copied = false
    @State private var hovering = false

    @ViewBuilder
    private var surface: some View {
        if appearance.settings.liquidGlass {
            ZStack {
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
        .overlay(alignment: .topTrailing) {
            if hovering { copyButton }
        }
        .onHover { hovering = $0 }
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
