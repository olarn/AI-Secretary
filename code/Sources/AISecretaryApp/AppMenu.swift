import AppKit
import SecretaryCore

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

    /// ⌘+ and ⌘− for the text size, the same thing the +/− buttons in Settings
    /// do. Unlike the editing items these can't travel the responder chain —
    /// nothing in it knows about the appearance — so they're aimed at an explicit
    /// target, which must outlive the menu.
    ///
    /// Both `+` and `=` are registered for growing: ⌘+ on most layouts is really
    /// ⌘⇧=, and people press it with and without the shift.
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

        // ⌘H hides the character, not the application. An accessory app has no
        // windows in the Dock to come back from, so `NSApplication.hide` mostly
        // just made the companion vanish with no obvious way to return it — and
        // hiding the character is the thing people actually want that key for.
        let hide = menu.addItem(
            withTitle: "Hide Character",
            action: #selector(AppCommands.toggleCharacter(_:)),
            keyEquivalent: "h"
        )
        hide.target = target
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

/// What the shortcut items call. Declared as a protocol so `AppMenu` can name
/// the selectors without depending on the delegate that implements them.
///
/// These can't travel the responder chain the way the editing items do —
/// nothing in it knows about the appearance or the character window — so each is
/// aimed at an explicit target, which must outlive the menu.
@MainActor
@objc protocol AppCommands {
    @objc func increaseTextSize(_ sender: Any?)
    @objc func decreaseTextSize(_ sender: Any?)
    @objc func toggleCharacter(_ sender: Any?)
    @objc func showAbout(_ sender: Any?)
}
