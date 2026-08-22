import AppKit
import SwiftUI
import SecretaryCore

private final class ResizablePanel: FloatingPanel {
    private let band: CGFloat = 6
    private(set) var isUserResizing = false

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
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

@MainActor
final class CommandWindowController {
    private let model: CommandCenter
    private var panel: FloatingPanel?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var arrowKeyMonitor: Any?
    private var naturalHeight: Double = 0
    private var builtFor: ObjectIdentifier?

    init(model: CommandCenter) {
        self.model = model
    }

    var isVisible: Bool { panel?.isVisible ?? false }
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
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusRequests += 1
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func builtPanel(using appearance: Appearance) -> FloatingPanel {
        if let panel {
            follow(appearance)
            return panel
        }

        let host = FirstMouseHostingView(rootView: builtView(using: appearance))
        host.sizingOptions = []

        let panel = ResizablePanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: commandWindowDefaultWidth, height: 160)),
            content: host,
            takesKeyOnClick: true
        )
        panel.appearance = appearance.colors.controlAppearance
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

    private func followContentHeight(_ height: Double) {
        guard let panel, height > 0 else { return }
        naturalHeight = max(1, height - model.extraBoxHeight)
        panel.contentMinSize = CGSize(width: 380, height: naturalHeight)
        panel.contentMaxSize = CGSize(width: 1000, height: 10_000)
        guard (panel as? ResizablePanel)?.isUserResizing != true else { return }
        guard abs(panel.frame.height - height) > 0.5 else { return }
        let top = panel.frame.maxY
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: top - height, width: panel.frame.width, height: height),
            display: true
        )
    }

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
