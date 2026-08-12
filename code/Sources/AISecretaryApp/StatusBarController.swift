import AppKit
import SecretaryCore

/// Gives the accessory app a real, native presence: a menu bar icon whose menu
/// reaches every character, the usage figures, the version, and — crucially —
/// a normal way to quit. Without a Dock icon or main menu, this is the standard
/// macOS control surface for a floating companion.
///
/// This type decides nothing. What the menu contains is `statusBarMenu(...)` in
/// `SecretaryCore`, where it is a value with tests; here it is turned into
/// `NSMenuItem`s and the clicks are handed back as actions. The split is the
/// charter's rule about `AISecretaryApp` being invisible to coverage, applied
/// to the one part of the app that was entirely decision and entirely untested.
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    /// Read fresh every time the menu opens rather than kept in step with every
    /// change. A menu only has to be right at the moment it is shown, and the
    /// things it lists — conversations, pinned panes, whether a character is
    /// showing — all change from elsewhere.
    private let menu: () -> [StatusMenuEntry]
    private let perform: (StatusMenuAction) -> Void

    init(
        menu: @escaping () -> [StatusMenuEntry],
        perform: @escaping (StatusMenuAction) -> Void
    ) {
        self.menu = menu
        self.perform = perform
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let target = Target(controller: self)
        self.target = target

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI Secretary")
                ?? NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "AI Secretary")
            button.image?.isTemplate = true
            button.toolTip = "AI Secretary"
        }

        let root = NSMenu()
        root.delegate = target
        statusItem.menu = root
        rebuild()
    }

    /// Retained so the menu items' target isn't deallocated.
    private var target: Target?

    private func rebuild() {
        guard let root = statusItem.menu else { return }
        root.removeAllItems()
        menu().forEach { root.addItem(build($0)) }
    }

    private func build(_ entry: StatusMenuEntry) -> NSMenuItem {
        switch entry {
        case .separator:
            return .separator()
        case .item(let spec):
            return build(spec)
        }
    }

    private func build(_ spec: StatusMenuItem) -> NSMenuItem {
        let item = NSMenuItem(
            title: spec.title,
            action: spec.action == nil ? nil : #selector(Target.perform(_:)),
            keyEquivalent: spec.shortcut?.rawValue ?? ""
        )
        if spec.shortcut != nil { item.keyEquivalentModifierMask = [.command] }
        if let action = spec.action {
            item.target = target
            item.representedObject = Box(action)
        }
        item.state = spec.isChecked ? .on : .off
        // macOS 26 draws an ⓘ beside anything it recognises as an About
        // command. Nothing here asked for it, and one icon in a menu of plain
        // rows reserves an icon column that indents every other title — so the
        // glyph is refused on every row, at every level.
        //
        // An empty image rather than `nil`: `nil` means "decide for me", which
        // is how the ⓘ arrived.
        item.image = NSImage(size: .zero)

        if let submenu = spec.submenu {
            let child = NSMenu(title: spec.title)
            submenu.forEach { child.addItem(build($0)) }
            item.submenu = child
        }

        // Last, and after the submenu: AppKit re-enables a parent when it is
        // given one, and `isEnabled` is how an empty Chat History is greyed.
        // Set before, it would be undone.
        item.isEnabled = spec.isEnabled
        return item
    }

    /// Actions are enums, and `representedObject` is `Any?` — which an enum
    /// with associated values cannot cross as itself under the Objective-C
    /// bridge without being boxed.
    private final class Box: NSObject {
        let action: StatusMenuAction
        init(_ action: StatusMenuAction) { self.action = action }
    }

    /// Objective-C selector target. `StatusBarController` isn't an `NSObject`, so
    /// this thin class receives the menu actions and forwards them.
    @MainActor
    private final class Target: NSObject, NSMenuDelegate {
        private unowned let controller: StatusBarController
        init(controller: StatusBarController) { self.controller = controller }

        @objc func perform(_ sender: Any?) {
            guard let box = (sender as? NSMenuItem)?.representedObject as? Box else { return }
            controller.perform(box.action)
        }

        func menuWillOpen(_ menu: NSMenu) {
            // Only the root: a submenu's contents were built with its parent a
            // moment ago and rebuilding them here would replace the items
            // AppKit is in the middle of showing.
            guard menu === controller.statusItem.menu else { return }
            controller.rebuild()
        }
    }
}
