import AppKit
import Carbon.HIToolbox
import SecretaryCore

/// Claims key combinations from the whole system, so they reach this app even
/// when another one is frontmost.
///
/// Carbon's `RegisterEventHotKey` is the only way to do this without the
/// Accessibility permission a `CGEventTap` demands, and it is the only one that
/// *consumes* the keystroke: `NSEvent.addGlobalMonitorForEvents` can watch but
/// not swallow, so ⌘H would hide the frontmost app as well as this one.
///
/// Why any of this is needed: a local monitor and a menu key equivalent both
/// only ever see events the system already decided to deliver here. With the
/// chat bubble floating above another app, Esc went to that app and the bubble
/// stayed — the handler was correct and the key never arrived.
@MainActor
final class GlobalHotKeys {
    /// Actions by shortcut, set once by the delegate.
    private let actions: [GlobalShortcut: () -> Void]
    private var registered: [GlobalShortcut: EventHotKeyRef] = [:]

    /// Carbon calls back into a C function that cannot capture context, so the
    /// live instance is reached through this.
    private static weak var current: GlobalHotKeys?
    private static var eventHandler: EventHandlerRef?

    init(actions: [GlobalShortcut: () -> Void]) {
        self.actions = actions
        Self.current = self
        Self.installDispatcher()
    }

    /// Brings the claimed set in line with `claimedShortcuts`. Safe to call on
    /// every visibility change: already-claimed keys are left alone.
    func apply(chatVisible: Bool) {
        let wanted = claimedShortcuts(chatVisible: chatVisible)
        for shortcut in registered.keys where !wanted.contains(shortcut) {
            release(shortcut)
        }
        for shortcut in wanted where registered[shortcut] == nil {
            claim(shortcut)
        }
    }

    func releaseAll() {
        for shortcut in registered.keys { release(shortcut) }
    }

    private func claim(_ shortcut: GlobalShortcut) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: shortcut.hotKeyID)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        // A refusal is not fatal: another app may already hold the combination,
        // in which case this one simply keeps working from its own windows.
        guard status == noErr, let ref else { return }
        registered[shortcut] = ref
    }

    private func release(_ shortcut: GlobalShortcut) {
        guard let ref = registered.removeValue(forKey: shortcut) else { return }
        UnregisterEventHotKey(ref)
    }

    // MARK: - Carbon plumbing

    /// `'AISC'`, so our hot key ids can't be confused with another app's.
    private static let signature: OSType = 0x41495343

    fileprivate static func fire(id: UInt32) {
        guard let shortcut = GlobalShortcut.allCases.first(where: { $0.hotKeyID == id }) else { return }
        current?.actions[shortcut]?()
    }

    private static func installDispatcher() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard status == noErr, id.signature == GlobalHotKeys.signature else { return noErr }
                let hotKeyID = id.id
                // Carbon delivers on the main thread, but the callback itself is
                // outside the actor, so hop rather than assert.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { GlobalHotKeys.fire(id: hotKeyID) }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }
}

private extension GlobalShortcut {
    /// Stable per-case id for Carbon, which identifies hot keys by number.
    var hotKeyID: UInt32 {
        switch self {
        case .hideApp: 1
        case .closeChat: 2
        }
    }
}
