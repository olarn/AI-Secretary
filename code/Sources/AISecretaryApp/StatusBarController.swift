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
    /// Panes pulled out of the chat. Read when the menu opens rather than kept
    /// in step with every change: a menu only has to be right at the moment it
    /// is shown, and rebuilding then means no stale rows.
    private let onNewConversation: () -> Void
    private let windows: () -> InfoWindows?
    private let windowsMenuItem: NSMenuItem
    /// Read fresh every time the menu opens rather than cached: a conversation
    /// is put away by `/new` in the chat as well as by this menu, and a copy
    /// kept here would be a day out of date the first time that happened.
    private let history: () -> [ConversationMenuRow]
    private let onResumeConversation: (UUID) -> Void
    private let onClearHistory: () -> Void
    private let historyMenuItem: NSMenuItem

    init(
        onOpenChat: @escaping () -> Void,
        onToggleCharacter: @escaping () -> Bool,
        onShowUsage: @escaping () -> Void,
        onNewConversation: @escaping () -> Void,
        history: @escaping () -> [ConversationMenuRow] = { [] },
        onResumeConversation: @escaping (UUID) -> Void = { _ in },
        onClearHistory: @escaping () -> Void = {},
        windows: @escaping () -> InfoWindows?
    ) {
        self.onOpenChat = onOpenChat
        self.onToggleCharacter = onToggleCharacter
        self.onShowUsage = onShowUsage
        self.onNewConversation = onNewConversation
        self.history = history
        self.onResumeConversation = onResumeConversation
        self.onClearHistory = onClearHistory
        self.historyMenuItem = NSMenuItem(title: "Chat History", action: nil, keyEquivalent: "")
        self.windows = windows
        self.windowsMenuItem = NSMenuItem(title: "Pinned Messages", action: nil, keyEquivalent: "")
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

        // Reachable from here as well as from `/new`, because the reason to
        // want it is often that the chat is in a state you'd rather not type
        // into.
        let newItem = NSMenuItem(
            title: "New Conversation",
            action: #selector(Target.newConversation(_:)),
            keyEquivalent: ""
        )
        newItem.target = target
        menu.addItem(newItem)

        // Directly under New Conversation, because they are two halves of one
        // idea: that one puts the current thread away, this is where it went.
        historyMenuItem.submenu = NSMenu(title: "Chat History")
        menu.addItem(historyMenuItem)

        // Everything above is about the conversation; everything below is about
        // the app. The line is where that changes.
        menu.addItem(.separator())

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

        windowsMenuItem.submenu = NSMenu(title: "Pinned Messages")
        menu.addItem(windowsMenuItem)
        menu.delegate = target

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
    fileprivate func handleNewConversation() { onNewConversation() }

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

    /// Rebuilt each time the menu opens.
    ///
    /// Each pane gets a submenu rather than a bare row: the list has to both
    /// bring a pane back and delete one, and an action hidden behind a modifier
    /// key is an action most people never find.
    fileprivate func rebuildWindowsMenu() {
        let submenu = NSMenu(title: "Pinned Messages")
        guard let windows = windows() else {
            windowsMenuItem.submenu = submenu
            windowsMenuItem.isEnabled = false
            return
        }

        let open = windows.set.windows
        windowsMenuItem.isEnabled = !open.isEmpty
        if open.isEmpty {
            let empty = NSMenuItem(title: "Nothing pinned yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            windowsMenuItem.submenu = submenu
            return
        }

        // One row per pane, and clicking it brings that pane to the front.
        // Deleting lives on the pane's own close button and on Clear All: a row
        // whose whole job is "show me this" should not need a submenu in front
        // of it, and a Delete sitting one pixel from Show is a mis-click waiting
        // to throw away the thing you meant to look at.
        for spec in open {
            let item = NSMenuItem(
                title: spec.title,
                action: #selector(Target.showWindow(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = spec.id
            submenu.addItem(item)
        }

        // Always last, in this order, so their positions don't move as panes
        // come and go.
        submenu.addItem(.separator())
        let showAll = NSMenuItem(
            title: "Show All",
            action: #selector(Target.showAllWindows(_:)),
            keyEquivalent: ""
        )
        showAll.target = target
        submenu.addItem(showAll)

        let clear = NSMenuItem(title: "Clear All", action: #selector(Target.clearWindows(_:)), keyEquivalent: "")
        clear.target = target
        submenu.addItem(clear)

        windowsMenuItem.submenu = submenu
    }

    /// Rebuilt on every open, for the same reason the pinned list is: the rows
    /// change from the chat window, not from here.
    fileprivate func rebuildHistoryMenu() {
        let submenu = NSMenu(title: "Chat History")
        let rows = history()
        historyMenuItem.isEnabled = !rows.isEmpty

        if rows.isEmpty {
            let empty = NSMenuItem(title: "No past conversations", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            historyMenuItem.submenu = submenu
            return
        }

        for row in rows {
            let item = NSMenuItem(
                title: row.label,
                action: #selector(Target.resumeConversation(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = row.id
            // Which one you are already in. Without it, reopening the
            // conversation you are looking at is an invisible no-op that reads
            // as the menu being broken.
            item.state = row.isCurrent ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear All", action: #selector(Target.clearHistory(_:)), keyEquivalent: "")
        clear.target = target
        submenu.addItem(clear)

        historyMenuItem.submenu = submenu
    }

    fileprivate func handleResumeConversation(_ id: UUID) { onResumeConversation(id) }
    fileprivate func handleClearHistory() { onClearHistory() }

    fileprivate func handleShowWindow(_ id: UUID) { windows()?.show(id) }
    fileprivate func handleShowAllWindows() { windows()?.showAll() }
    fileprivate func handleClearWindows() { windows()?.clearAll() }

    fileprivate func handleShowAbout() { AboutPanel.show() }

    fileprivate func handleQuit() { NSApp.terminate(nil) }

    /// Objective-C selector target. `StatusBarController` isn't an `NSObject`, so
    /// this thin class receives the menu actions and forwards them.
    @MainActor
    private final class Target: NSObject, NSMenuDelegate {
        private unowned let controller: StatusBarController
        init(controller: StatusBarController) { self.controller = controller }

        @objc func openChat(_ sender: Any?) { controller.handleOpenChat() }
        @objc func toggleCharacter(_ sender: Any?) { controller.handleToggleCharacter() }
        @objc func showUsage(_ sender: Any?) { controller.handleShowUsage() }
        @objc func newConversation(_ sender: Any?) { controller.handleNewConversation() }

        @objc func showWindow(_ sender: Any?) {
            guard let id = (sender as? NSMenuItem)?.representedObject as? UUID else { return }
            controller.handleShowWindow(id)
        }

        @objc func showAllWindows(_ sender: Any?) { controller.handleShowAllWindows() }

        @objc func clearWindows(_ sender: Any?) { controller.handleClearWindows() }

        @objc func resumeConversation(_ sender: Any?) {
            guard let id = (sender as? NSMenuItem)?.representedObject as? UUID else { return }
            controller.handleResumeConversation(id)
        }

        @objc func clearHistory(_ sender: Any?) { controller.handleClearHistory() }

        func menuWillOpen(_ menu: NSMenu) {
            controller.rebuildWindowsMenu()
            controller.rebuildHistoryMenu()
        }
        @objc func showAbout(_ sender: Any?) { controller.handleShowAbout() }
        @objc func quit(_ sender: Any?) { controller.handleQuit() }
    }
}
