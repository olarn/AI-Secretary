import AppKit
import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import LLMProvider

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppCommands {
    // What belongs to the app rather than to any one character: the look, the
    // roster, where work may run, and the single status bar item. A character's
    // own world — her Secretary, her windows, her Claude Code session — lives
    // in `CharacterInstance`.
    private let registry = ProjectRegistry()
    private let backendStatus = BackendStatus()
    private let appearance = Appearance()
    private let profiles = ProfileLibrary()
    /// Where Claude Code is — the machine's answer, found once and handed to
    /// every character. The session built on top of it is hers; this is not.
    private let detector = ClaudeCodeDetector()

    /// The characters on the desktop. One for now; the point of the type is
    /// that this becomes several without the delegate changing shape.
    private var characters: [CharacterInstance] = []
    /// The one the menu and the app-wide shortcuts act on. With a single
    /// character it is simply that character.
    private var focused: CharacterInstance! { characters.first }

    private var statusBar: StatusBarController!
    private var hotKeys: GlobalHotKeys?
    /// Watches this app's own key events for ⌘H; see `watchForHideShortcut`.
    private var hideKeyMonitor: Any?
    private lazy var usageWindow = UsageWindow(
        secretary: focused.secretary,
        appearance: appearance,
        backend: focused.backend
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let character = CharacterInstance(
            profileID: profiles.activeID,
            profiles: profiles,
            appearance: appearance,
            registry: registry,
            backendStatus: backendStatus,
            detector: detector,
            // The one place that should touch the real files. Everywhere else —
            // every test — gets the in-memory defaults and cannot reach them.
            conversationStore: FileConversationStore(),
            attachmentStore: FileAttachmentStore()
        )
        characters = [character]
        character.onDismissableChanged = { [weak self] in self?.refreshHotKeyClaim() }
        character.onVisibilityChanged = { [weak self] visible in
            self?.statusBar?.setCharacterVisible(visible)
        }
        character.buildWindows(onClose: { [weak self] in self?.focused.hideChatPanel() })

        detectBackend()

        // Resizing an NSPanel is imperative work, so the model calls back here
        // rather than the delegate re-deriving it during a view update.
        appearance.onChange = { [weak self] in
            self?.characters.forEach { $0.applyWindowSizes() }
            self?.applyControlAppearance()
        }
        applyControlAppearance()
        // Switching profile has to reach the prompt as well as the pictures.
        profiles.onActiveChange = { [weak self] profile in
            self?.focused.secretary.apply(profile: profile)
        }

        statusBar = StatusBarController(
            onOpenChat: { [weak self] in self?.focused.openChat() },
            onToggleCharacter: { [weak self] in self?.focused.toggleCharacterVisibility() ?? true },
            onShowUsage: { [weak self] in self?.usageWindow.toggle() },
            onNewConversation: { [weak self] in
                self?.focused.secretary.newConversation()
                // Starting a conversation means having one. Clearing the slate
                // behind a hidden window would leave nothing to show for the
                // click, and the bubble being closed is a common reason to
                // reach for the menu in the first place.
                self?.focused.openChat()
            },
            history: { [weak self] in self?.focused.secretary.historyRows() ?? [] },
            onResumeConversation: { [weak self] id in
                self?.focused.secretary.resumeConversation(id)
                // Reopening a conversation from the menu means wanting to look
                // at it, and the bubble may well be hidden — that is often why
                // the menu was used at all.
                self?.focused.openChat()
            },
            onClearHistory: { [weak self] in self?.focused.secretary.clearHistory() },
            windows: { [weak self] in self?.focused.infoWindows }
        )

        // Esc is claimed from the whole system, so the bubble answers it while
        // the user is typing in another app. Only Esc, and only while the chat
        // is showing — see `GlobalShortcut` for why ⌘H is not in this list.
        hotKeys = GlobalHotKeys(actions: [
            // Esc means "put away whatever is in front".
            .closeChat: { [weak self] in self?.focused.dismissFrontmost() }
        ])
        refreshHotKeyClaim()
        watchForHideShortcut()

        character.showCharacter()
    }

    /// ⌘H, taken from this app's own event stream while one of its windows has
    /// the keyboard.
    ///
    /// The menu item can't do it alone. The chat bubble is a non-activating
    /// panel: it takes the keyboard without making the app frontmost, and a menu
    /// key equivalent is only searched in the *active* app's menu — so pressing
    /// ⌘H while typing in the bubble hid whatever was behind it instead. A local
    /// monitor sees the event because the key window is ours, which is exactly
    /// the condition under which the shortcut should be ours.
    ///
    /// Local, not a Carbon hot key: taking ⌘H from the whole system broke Hide
    /// in every other app once already, and this claim ends the moment the
    /// keyboard does.
    private func watchForHideShortcut() {
        hideKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard handlesHideLocally(
                isOurWindowKey: NSApp.keyWindow != nil,
                key: event.charactersIgnoringModifiers ?? "",
                hasOnlyCommand: flags == .command
            ) else { return event }
            self.hideEverything()
            return nil
        }
    }

    /// What ⌘H does: the character and the chat both go away, which is what the
    /// menu item has always done. An accessory app has no Dock tile to come back
    /// from, so `NSApplication.hide` would leave nothing to click.
    private func hideEverything() {
        characters.filter(\.isCharacterVisible).forEach { $0.toggleCharacterVisibility() }
    }

    /// Esc is worth claiming only while something is on screen to dismiss —
    /// a chat bubble or a pinned pane. Called from the characters, since any of
    /// them can be the last one standing.
    func refreshHotKeyClaim() {
        hotKeys?.apply(hasDismissableWindow: characters.contains(where: \.hasDismissableWindow))
    }

    /// Hands Esc back to the rest of the system on the way out. The process
    /// dying releases it anyway; doing it explicitly means a slow teardown
    /// can't leave the key claimed by a window that's already gone.
    func applicationWillTerminate(_ notification: Notification) {
        hotKeys?.releaseAll()
    }

    /// Launching the app again while it is already running.
    ///
    /// macOS does not start a second process — it reactivates this one and
    /// sends this. With the character hidden, nothing at all would appear, and
    /// double-clicking the app again is exactly what someone does when they
    /// can't see it. Hiding is for getting it out of the way for a moment, not
    /// a setting to be remembered, so reopening always brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        focused?.showCharacter()
        return true
    }

    // MARK: - Menu commands

    /// ⌘+ / ⌘−, doing exactly what the +/− buttons in Settings do. Wired here
    /// rather than in the panel because the shortcut has to work whenever the
    /// app is active, including when the chat is closed.
    func increaseTextSize(_ sender: Any?) { appearance.increaseFontSize() }

    func decreaseTextSize(_ sender: Any?) { appearance.decreaseFontSize() }

    /// ⌘H. Goes through the same toggle the status bar item uses; the character
    /// reports back so the menu's wording doesn't go stale.
    func toggleCharacter(_ sender: Any?) { focused.toggleCharacterVisibility() }

    func showAbout(_ sender: Any?) { AboutPanel.show() }

    func toggleUsageWindow(_ sender: Any?) { usageWindow.toggle() }

    /// Finds Claude Code off the main thread. The fast path is a handful of
    /// `stat` calls, but the fallback launches the user's login shell, which can
    /// take seconds — doing that here would delay the character appearing.
    ///
    /// Asked of the detector rather than of a character's backend: the answer
    /// is the machine's, every backend is already watching for it, and running
    /// it once is the point of the split.
    private func detectBackend() {
        detector.observe { [weak self] availability in
            Task { @MainActor in self?.backendStatus.availability = availability }
        }
        let detector = self.detector
        Task.detached(priority: .utility) { detector.resolve() }
    }

    /// Re-lights every window the app owns when the theme changes.
    private func applyControlAppearance() {
        let controls = appearance.colors.controlAppearance
        characters.forEach { $0.applyControlAppearance(controls) }
        usageWindow.applyControlAppearance(controls)
    }
}
