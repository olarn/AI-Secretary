import AppKit
import SecretaryCore

@MainActor
enum AppMenu {
    static func make(appName: String = AppInfo.name, commandTarget: AnyObject? = nil) -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = applicationMenu(appName: appName, target: commandTarget)
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        editItem.submenu = editMenu()
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        viewItem.submenu = viewMenu(target: commandTarget)
        mainMenu.addItem(viewItem)

        return mainMenu
    }

    private static func viewMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "View")
        let bigger = #selector(AppCommands.increaseTextSize(_:))
        let smaller = #selector(AppCommands.decreaseTextSize(_:))

        for key in ["+", "="] {
            let item = menu.addItem(withTitle: "Bigger Text", action: bigger, keyEquivalent: key)
            item.target = target
        }
        let smallerItem = menu.addItem(withTitle: "Smaller Text", action: smaller, keyEquivalent: "-")
        smallerItem.target = target

        return menu
    }

    private static func applicationMenu(appName: String, target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: appName)

        let about = menu.addItem(
            withTitle: "About \(appName)",
            action: #selector(AppCommands.showAbout(_:)),
            keyEquivalent: ""
        )
        about.target = target
        menu.addItem(.separator())

        let usage = menu.addItem(
            withTitle: "Token Usage",
            action: #selector(AppCommands.toggleUsageWindow(_:)),
            keyEquivalent: "u"
        )
        usage.target = target
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        return menu
    }
}

@MainActor
@objc protocol AppCommands {
    @objc func increaseTextSize(_ sender: Any?)
    @objc func decreaseTextSize(_ sender: Any?)
    @objc func showAbout(_ sender: Any?)
    @objc func toggleUsageWindow(_ sender: Any?)
}
