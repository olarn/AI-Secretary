import AppKit
import SecretaryCore

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
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
            action: spec.action == nil ? nil : #selector(Target.menuItemClicked(_:)),
            keyEquivalent: spec.shortcut?.rawValue ?? ""
        )
        if spec.shortcut != nil { item.keyEquivalentModifierMask = [.command] }
        if let action = spec.action {
            item.target = target
            item.representedObject = Box(action)
        }
        item.state = spec.isChecked ? .on : .off
        item.image = NSImage(size: .zero)

        if let submenu = spec.submenu {
            let child = NSMenu(title: spec.title)
            submenu.forEach { child.addItem(build($0)) }
            item.submenu = child
        }

        item.isEnabled = spec.isEnabled
        return item
    }

    private final class Box: NSObject {
        let action: StatusMenuAction
        init(_ action: StatusMenuAction) { self.action = action }
    }

    @MainActor
    private final class Target: NSObject, NSMenuDelegate {
        private unowned let controller: StatusBarController
        init(controller: StatusBarController) { self.controller = controller }

        @objc func menuItemClicked(_ sender: Any?) {
            guard let box = (sender as? NSMenuItem)?.representedObject as? Box else { return }
            controller.perform(box.action)
        }

        func menuWillOpen(_ menu: NSMenu) {
            guard menu === controller.statusItem.menu else { return }
            controller.rebuild()
        }
    }
}
