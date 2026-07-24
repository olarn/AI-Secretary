import AppKit

/// Gives the accessory app a real, native presence: a menu bar icon whose menu
/// lets the user open the chat, show/hide the character, and — crucially — quit
/// the app normally. Without a Dock icon or main menu, this is the standard
/// macOS control surface for a floating companion.
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let characterMenuItem: NSMenuItem

    /// Callbacks into the app, kept as closures so this stays UI-only and doesn't
    /// need to know about panels or the Secretary.
    private let onOpenChat: () -> Void
    private let onToggleCharacter: () -> Bool // returns the new "is visible" state

    init(onOpenChat: @escaping () -> Void, onToggleCharacter: @escaping () -> Bool) {
        self.onOpenChat = onOpenChat
        self.onToggleCharacter = onToggleCharacter
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

        let header = NSMenuItem(title: "AI Secretary", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Chat", action: #selector(Target.openChat(_:)), keyEquivalent: "")
        openItem.target = target
        menu.addItem(openItem)

        characterMenuItem.target = target
        menu.addItem(characterMenuItem)

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
        let isVisible = onToggleCharacter()
        characterMenuItem.title = isVisible ? "Hide Character" : "Show Character"
    }

    fileprivate func handleQuit() { NSApp.terminate(nil) }

    /// Objective-C selector target. `StatusBarController` isn't an `NSObject`, so
    /// this thin class receives the menu actions and forwards them.
    @MainActor
    private final class Target: NSObject {
        private unowned let controller: StatusBarController
        init(controller: StatusBarController) { self.controller = controller }

        @objc func openChat(_ sender: Any?) { controller.handleOpenChat() }
        @objc func toggleCharacter(_ sender: Any?) { controller.handleToggleCharacter() }
        @objc func quit(_ sender: Any?) { controller.handleQuit() }
    }
}
