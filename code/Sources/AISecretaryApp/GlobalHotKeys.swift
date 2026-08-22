import AppKit
import Carbon.HIToolbox
import SecretaryCore

@MainActor
final class GlobalHotKeys {
    private let actions: [GlobalShortcut: () -> Void]
    private var registered: [GlobalShortcut: EventHotKeyRef] = [:]

    private static weak var current: GlobalHotKeys?
    private static var eventHandler: EventHandlerRef?

    init(actions: [GlobalShortcut: () -> Void]) {
        self.actions = actions
        Self.current = self
        Self.installDispatcher()
    }

    func apply(hasDismissableWindow: Bool) {
        let wanted = claimedShortcuts(hasDismissableWindow: hasDismissableWindow)
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

    static func whileSuspended<T>(_ body: () -> T) -> T {
        guard let keys = current else { return body() }
        let held = Set(keys.registered.keys)
        keys.releaseAll()
        defer { for shortcut in held { keys.claim(shortcut) } }
        return body()
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
        guard status == noErr, let ref else { return }
        registered[shortcut] = ref
    }

    private func release(_ shortcut: GlobalShortcut) {
        guard let ref = registered.removeValue(forKey: shortcut) else { return }
        UnregisterEventHotKey(ref)
    }

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
    var hotKeyID: UInt32 {
        switch self {
        case .closeChat: 2
        }
    }
}
