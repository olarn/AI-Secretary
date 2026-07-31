import AppKit
import SecretaryCore

/// Gives the accessory app a real, native presence: a menu bar icon whose menu
/// lets the user open the chat, show/hide the character, see which version this
/// is, and — crucially — quit the app normally. Without a Dock icon or main
/// menu, this is the standard macOS control surface for a floating companion.
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let characterMenuItem: NSMenuItem

    /// Callbacks into the app, kept as closures so this stays UI-only and doesn't
    /// need to know about panels or the Secretary.
    private let onOpenChat: () -> Void
    private let onToggleCharacter: () -> Bool // returns the new "is visible" state
    private let onShowUsage: () -> Void

    init(
        onOpenChat: @escaping () -> Void,
        onToggleCharacter: @escaping () -> Bool,
        onShowUsage: @escaping () -> Void
    ) {
        self.onOpenChat = onOpenChat
        self.onToggleCharacter = onToggleCharacter
        self.onShowUsage = onShowUsage
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.characterMenuItem = NSMenuItem(
            title: "Hide Character",
            action: #selector(Target.toggleCharacter(_:)),
            keyEquivalent: ""
        )

        let target = Target(controller: self)
        self.target = target

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI Secretary")
                ?? NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "AI Secretary")
            button.image?.isTemplate = true
            button.toolTip = "AI Secretary"
        }

        let menu = NSMenu()

        // The version rides in the disabled header rather than being a row of
        // its own: it's a label, not something to click, and it answers "which
        // build am I running" without opening anything.
        let header = NSMenuItem(title: AppInfo.summary, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Chat", action: #selector(Target.openChat(_:)), keyEquivalent: "")
        openItem.target = target
        menu.addItem(openItem)

        // ⌘H matches the shortcut in the (undrawn) main menu, and showing it here
        // is how the user finds out the shortcut exists at all.
        characterMenuItem.target = target
        characterMenuItem.keyEquivalent = "h"
        characterMenuItem.keyEquivalentModifierMask = [.command]
        menu.addItem(characterMenuItem)

        // Its own window rather than a row in the chat: the figures are for
        // leaving open next to the work, and closing the chat must not take
        // them away.
        let usageItem = NSMenuItem(
            title: "Token Usage",
            action: #selector(Target.showUsage(_:)),
            keyEquivalent: "u"
        )
        usageItem.keyEquivalentModifierMask = [.command]
        usageItem.target = target
        menu.addItem(usageItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About \(AppInfo.name)",
            action: #selector(Target.showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = target
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit AI Secretary", action: #selector(Target.quit(_:)), keyEquivalent: "q")
        quitItem.target = target
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// Retained so the menu items' target isn't deallocated.
    private var target: Target?

    fileprivate func handleOpenChat() { onOpenChat() }

    fileprivate func handleToggleCharacter() {
        setCharacterVisible(onToggleCharacter())
    }

    /// Keeps the item's wording honest when the character is toggled from
    /// somewhere else — ⌘H reaches the app delegate directly, and a menu still
    /// offering to "Hide Character" after it's already hidden is a bug the user
    /// only finds by opening the menu.
    func setCharacterVisible(_ isVisible: Bool) {
        characterMenuItem.title = isVisible ? "Hide Character" : "Show Character"
    }

    fileprivate func handleShowUsage() { onShowUsage() }

    fileprivate func handleShowAbout() { AboutPanel.show() }

    fileprivate func handleQuit() { NSApp.terminate(nil) }

    /// Objective-C selector target. `StatusBarController` isn't an `NSObject`, so
    /// this thin class receives the menu actions and forwards them.
    @MainActor
    private final class Target: NSObject {
        private unowned let controller: StatusBarController
        init(controller: StatusBarController) { self.controller = controller }

        @objc func openChat(_ sender: Any?) { controller.handleOpenChat() }
        @objc func toggleCharacter(_ sender: Any?) { controller.handleToggleCharacter() }
        @objc func showUsage(_ sender: Any?) { controller.handleShowUsage() }
        @objc func showAbout(_ sender: Any?) { controller.handleShowAbout() }
        @objc func quit(_ sender: Any?) { controller.handleQuit() }
    }
}
