import AppKit

/// Builds the application's main menu.
///
/// The app runs with `.accessory` activation policy, so this menu is never
/// *drawn* — there is no menu bar for an agent app. It still has to exist:
/// `NSApplication` matches command-key equivalents against `mainMenu` before
/// anything else, so without it ⌘Q, ⌘C, ⌘V and friends simply do nothing while
/// the app is active. Installing an invisible menu is the supported way to give
/// a menu-bar-only app the standard keyboard shortcuts.
///
/// Every item targets `nil` so it travels the responder chain: Quit reaches
/// `NSApplication`, and the editing items reach whichever text field is first
/// responder inside the chat panel.
@MainActor
enum AppMenu {
    static func make(appName: String = "AI Secretary") -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = applicationMenu(appName: appName)
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        editItem.submenu = editMenu()
        mainMenu.addItem(editItem)

        return mainMenu
    }

    private static func applicationMenu(appName: String) -> NSMenu {
        let menu = NSMenu(title: appName)
        menu.addItem(
            withTitle: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    /// Standard editing shortcuts. Without these the chat text field has no
    /// copy, paste, select-all or undo — a real gap in an app whose only input
    /// is a text field.
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
