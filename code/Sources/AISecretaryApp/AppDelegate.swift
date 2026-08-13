import AppKit
import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import LLMProvider

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppCommands {
    // What belongs to the app rather than to any one character: the look, the
    // roster, and the single status bar item. A character's own world — her
    // Secretary, her windows, her Claude Code session, and since 13-1 the
    // projects she may work in — lives in `CharacterInstance`.
    private let backendStatus = BackendStatus()
    private let profiles = ProfileLibrary()
    /// Where Claude Code is — the machine's answer, found once and handed to
    /// every character. The session built on top of it is hers; this is not.
    private let detector = ClaudeCodeDetector()

    /// The characters on the desktop. One for now; the point of the type is
    /// that this becomes several without the delegate changing shape.
    private var characters: [CharacterInstance] = []
    /// The one the menu and the app-wide shortcuts act on: whoever was last
    /// worked with, falling back to the first on the desktop.
    ///
    /// It matters more since 13-1 than it did when it was simply
    /// `characters.first`. Token Usage and About have no look of their own, so
    /// this is also the character whose theme and text size they borrow.
    private var focused: CharacterInstance! {
        lastUsed.flatMap(character) ?? characters.first
    }
    private var lastUsed: UUID?

    private var statusBar: StatusBarController!
    private var hotKeys: GlobalHotKeys?
    /// Watches this app's own key events for ⌘H; see `watchForHideShortcut`.
    private var hideKeyMonitor: Any?
    /// Who the usage window adds up. Kept in step by `reconcileCharacters`.
    private let usageRoster = UsageRoster()
    private lazy var usageWindow = UsageWindow(
        roster: usageRoster,
        backend: focused.backend
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Every profile is a character, and every character is on the desktop.
        reconcileCharacters()
        // Adding or deleting a profile is adding or deleting a character; the
        // roster follows the library rather than being kept in step by hand.
        profiles.onRosterChange = { [weak self] in self?.reconcileCharacters() }

        detectBackend()

        applyControlAppearance()
        // Renaming or re-describing a character has to reach her prompt, not
        // just her label.
        profiles.onProfileChange = { [weak self] profile in
            self?.character(profile.id)?.secretary.apply(profile: profile)
        }

        statusBar = StatusBarController(
            menu: { [weak self] in self?.menuState() ?? [] },
            perform: { [weak self] action in self?.perform(action) }
        )

        // Esc is claimed from the whole system, so the bubble answers it while
        // the user is typing in another app. Only Esc, and only while the chat
        // is showing — see `GlobalShortcut` for why ⌘H is not in this list.
        hotKeys = GlobalHotKeys(actions: [
            // Esc means "put away whatever is in front" — for whichever
            // character that is. `dismissTarget` decides; this only asks the
            // windows who has the keyboard.
            .closeChat: { [weak self] in self?.dismissWhateverIsInFront() }
        ])
        refreshHotKeyClaim()
        watchForHideShortcut()

        characters.forEach { $0.showCharacter() }
    }

    // MARK: - The roster

    /// Brings the characters on screen into line with the profiles that exist.
    ///
    /// Written as a reconcile rather than as "add this one" / "remove that one"
    /// so that add, delete and launch are the same code path — the alternative
    /// is three places that can disagree about who is on the desktop.
    private func reconcileCharacters() {
        let wanted = profiles.profiles.map(\.id)

        characters
            .filter { !wanted.contains($0.profileID) }
            .forEach { $0.tearDown() }
        characters.removeAll { !wanted.contains($0.profileID) }

        for id in wanted where character(id) == nil {
            let fresh = makeCharacter(id, ordinal: characters.count)
            characters.append(fresh)
            fresh.showCharacter()
        }

        usageRoster.characters = characters.map {
            (name: profiles.profile($0.profileID).displayName, secretary: $0.secretary)
        }
        applyControlAppearance()
        refreshHotKeyClaim()
    }

    private func makeCharacter(_ id: UUID, ordinal: Int) -> CharacterInstance {
        let character = CharacterInstance(
            profileID: id,
            profiles: profiles,
            appearance: Appearance(character: id),
            registry: ProjectRegistry(store: FileProjectStore(fileURL: projectsFile(for: id))),
            backendStatus: backendStatus,
            detector: detector,
            // The one place that should touch the real files. Everywhere else —
            // every test — gets the in-memory defaults and cannot reach them.
            conversationStore: FileConversationStore(fileURL: historyFile(for: id)),
            attachmentStore: FileAttachmentStore()
        )
        character.onDismissableChanged = { [weak self] in self?.refreshHotKeyClaim() }
        character.onUsed = { [weak self] in self?.lastUsed = id }
        // Her settings resize and re-light her own windows, and nobody else's.
        // This was one callback for the whole app when there was one look to
        // apply; now applying one character's theme to all of them is precisely
        // the bug.
        character.appearance.onChange = { [weak character] in
            character?.applyWindowSizes()
            character?.applyOwnControlAppearance()
        }
        character.buildWindows(
            ordinal: ordinal,
            onClose: { [weak character] in character?.hideChatPanel() }
        )
        return character
    }

    /// This character's own history file, adopting the one everybody shared
    /// before characters had their own.
    ///
    /// The failure is discarded on purpose, and explicitly rather than by
    /// omission: it can only be a rename that didn't happen, the character then
    /// starts with an empty history instead of her old one, and there is no
    /// useful thing to say about it while the app is still opening. Nothing is
    /// deleted either way — the old file is still there to adopt next launch.
    private func historyFile(for id: UUID) -> URL {
        _ = FileConversationStore.adoptLegacyHistory(for: id)
        return FileConversationStore.url(forCharacter: id)
    }

    /// This character's own project registry, adopting the one everybody shared
    /// before characters had their own. Same shape as `historyFile`, and the
    /// failure is discarded for the same reason.
    ///
    /// What she adopts is an allowlist, not a list of folders: a project row
    /// carries the tools approved for it. Whoever is built first takes it, and
    /// nobody else inherits those approvals — which is the whole point, and is
    /// also why a second character starts with none.
    private func projectsFile(for id: UUID) -> URL {
        _ = FileProjectStore.adoptLegacyProjects(for: id)
        return FileProjectStore.url(forCharacter: id)
    }

    // MARK: - The status bar menu

    /// Reads the current state of every character for `statusBarMenu`, which
    /// decides what the menu contains. Gathering, not deciding.
    private func menuState() -> [StatusMenuEntry] {
        statusBarMenu(
            summary: AppInfo.summary,
            characters: characters.map { character in
                CharacterMenuState(
                    id: character.profileID,
                    name: profiles.profiles.first { $0.id == character.profileID }?.displayName
                        ?? profiles.active.displayName,
                    isVisible: character.isCharacterVisible,
                    history: character.secretary.historyRows(),
                    pinned: character.infoWindows.set.windows.map {
                        PinnedMenuRow(id: $0.id, title: $0.title)
                    }
                )
            }
        )
    }

    /// Applies what a menu row asked for. Every case names the character it is
    /// about, so nothing here has to guess which one the click meant.
    private func perform(_ action: StatusMenuAction) {
        switch action {
        case .toggleCharacter(let id):
            character(id)?.toggleCharacterVisibility()
        case .newChat(let id):
            guard let character = character(id) else { return }
            character.secretary.newConversation()
            // Starting a conversation means having one. Clearing the slate
            // behind a hidden window would leave nothing to show for the click,
            // and the bubble being closed is a common reason to reach for the
            // menu in the first place.
            character.openChat()
        case .resumeConversation(let id, let conversation):
            guard let character = character(id) else { return }
            character.secretary.resumeConversation(conversation)
            // Reopening a conversation from the menu means wanting to look at
            // it, and the bubble may well be hidden — that is often why the
            // menu was used at all.
            character.openChat()
        case .clearHistory(let id):
            character(id)?.secretary.clearHistory()
        case .showPinned(let id, let window):
            character(id)?.infoWindows.show(window)
        case .showAllPinned(let id):
            character(id)?.infoWindows.showAll()
        case .clearPinned(let id):
            character(id)?.infoWindows.clearAll()
        case .newCharacter:
            // Cloned from whoever is focused, so "another one like this" is one
            // click. What she inherits and what she is called are decided by
            // `newCharacterDraft`; adding her to the library brings her window
            // up through `reconcileCharacters`.
            let template = focused.map { profiles.profile($0.profileID) } ?? profiles.active
            let fresh = newCharacterDraft(from: template, existing: profiles.profiles)
            profiles.add(fresh)
            character(fresh.id)?.openChat()
        case .showTokenUsage:
            usageWindow.toggle(using: focused.appearance)
        case .showAbout:
            AboutPanel.show()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func character(_ id: UUID) -> CharacterInstance? {
        characters.first { $0.profileID == id }
    }

    /// Esc. The system grants the key once, so one character has to be picked;
    /// the rule is `dismissTarget`, and this gathers what it needs.
    private func dismissWhateverIsInFront() {
        let target = dismissTarget(characters.map {
            DismissCandidate(
                id: $0.profileID,
                holdsKeyboard: $0.holdsKeyboard,
                hasDismissable: $0.hasDismissableWindow
            )
        })
        target.flatMap(character)?.dismissFrontmost()
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
    ///
    /// It resizes the text of one character — whoever was last worked with —
    /// now that the size is hers rather than the app's. A shortcut that changed
    /// all of them would be the one thing on this screen that still treats them
    /// as one.
    func increaseTextSize(_ sender: Any?) { focused?.appearance.increaseFontSize() }

    func decreaseTextSize(_ sender: Any?) { focused?.appearance.decreaseFontSize() }

    /// ⌘H. Goes through the same toggle the status bar item uses; the character
    /// reports back so the menu's wording doesn't go stale.
    func toggleCharacter(_ sender: Any?) { focused.toggleCharacterVisibility() }

    func showAbout(_ sender: Any?) { AboutPanel.show() }

    func toggleUsageWindow(_ sender: Any?) { usageWindow.toggle(using: focused.appearance) }

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

    /// Re-lights every window, each character from her own theme.
    ///
    /// Token Usage has no theme of its own and takes the focused character's,
    /// which is the same one it was built with unless the person has since gone
    /// and worked with somebody else — `show(using:)` catches that case.
    private func applyControlAppearance() {
        characters.forEach { $0.applyOwnControlAppearance() }
        usageWindow.applyControlAppearance(focused?.appearance.colors.controlAppearance)
    }
}
