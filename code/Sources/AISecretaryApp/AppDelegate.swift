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

    /// How the characters reach each other. Asks for the roster rather than
    /// holding it, so a character added or deleted needs nothing rewired.
    private lazy var bus = CharacterBus(roster: { [weak self] in self?.characters ?? [] })

    /// Banners for work that finished while nobody was watching, and the way
    /// back in when one is clicked.
    private lazy var notifier = CompletionNotifier(
        onOpen: { [weak self] id in self?.openFromNotification(id) }
    )

    private var statusBar: StatusBarController!
    private var hotKeys: GlobalHotKeys?
    /// Watches this app's own key events for ⌘H; see `watchForHideShortcut`.
    private var hideKeyMonitor: Any?
    /// The same, for Esc with nothing left to put away; see `watchForDismissKey`.
    private var dismissKeyMonitor: Any?
    /// Who ⌘H took off the desktop, so reopening puts back exactly them.
    private var hiddenByShortcut: Set<UUID> = []
    /// Who had a chat open when everything went away, so "Show All" can put the
    /// conversation back rather than only the characters.
    private var chatsHiddenByShortcut: Set<UUID> = []
    /// Whether ⌘H took the command window too, so Show All brings it back.
    private var commandHiddenByShortcut = false

    /// The command window's state: who is ticked, and who has been commanded.
    /// Delivery goes through `submit` — a broadcast is the same act as typing
    /// the same thing in each ticked character's own chat, which is the whole
    /// promise of the window.
    private lazy var commandCenter = CommandCenter(
        roster: { [weak self] in (self?.characters ?? []).map(\.card) },
        deliver: { [weak self] id, text, files in
            guard let secretary = self?.character(id)?.secretary else { return }
            // Attachments first, so the submit that follows carries them —
            // the same order typing in her own chat produces.
            files.forEach { secretary.attach($0) }
            secretary.submit(text)
        },
        endSessions: { [weak self] ids in
            ids.forEach { self?.character($0)?.secretary.newConversation() }
        },
        answerApproval: { [weak self] id, answer in
            self?.character(id)?.secretary.resolvePendingApproval(answer: answer)
        }
    )
    // No visibility callback: the status menu rebuilds itself every time it
    // opens, which is the only moment its wording can be seen.
    private lazy var commandWindow = CommandWindowController(model: commandCenter)

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

        // Before this method returns: a click on a banner may be what launched
        // the app, and the system delivers it the moment a delegate exists.
        notifier.start()

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
            // character that is. `dismissDecision` decides; this only asks the
            // windows who has the keyboard.
            .closeChat: { [weak self] in self?.dismissWhateverIsInFront(trigger: .hotKey) }
        ])
        refreshHotKeyClaim()
        watchForHideShortcut()
        watchForDismissKey()

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
        // Who else is on the desktop, and how to reach them. Read at the start
        // of each turn rather than pushed, so a character added or renamed
        // mid-session is simply there in the next prompt.
        character.secretary.directorySnapshot = { [weak self] in
            self?.bus.directory(excluding: id) ?? []
        }
        character.secretary.onSend = { [weak self] message in self?.bus.deliver(message) }
        character.secretary.onTurnFinished = { [weak self] turn in self?.announce(turn, from: id) }
        // A card raised while she is under command belongs where the person is
        // looking. Told both ways: put up, and taken down again.
        character.secretary.onApprovalAsked = { [weak self] asked in
            self?.commandCenter.record(asked, from: id)
        }
        character.secretary.onApprovalSettled = { [weak self] in
            self?.commandCenter.approvalSettled(for: id)
        }
        character.onUsed = { [weak self] in
            guard self?.lastUsed != id else { return }
            self?.lastUsed = id
            // Token Usage is wearing somebody's look and the somebody just
            // changed. Doing this only when the window is reopened left it in
            // the previous character's theme for as long as it stayed open.
            self?.applyControlAppearance()
        }
        // Her settings resize her own windows and nobody else's — this was one
        // callback for the whole app when there was one look to apply, and
        // applying one character's theme to all of them is now precisely the
        // bug.
        //
        // The re-lighting still goes through the app-wide sweep, though, and
        // that is not a leftover. Token Usage has no theme of its own and is
        // wearing the focused character's; when she changes hers while it is
        // open, nothing else would tell it. Driven at 0.13.216 before this
        // line existed: its body went light and its title bar stayed dark.
        character.appearance.onChange = { [weak self, weak character] in
            character?.applyWindowSizes()
            self?.applyControlAppearance()
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

    // MARK: - Notifications

    /// A character has finished something. Whether that is worth a banner is
    /// `completionNotice`'s decision — this only gathers the one fact she
    /// cannot see from inside herself: whether her chat is on screen.
    private func announce(_ turn: FinishedTurn, from id: UUID) {
        // The command window's results strip hears about every commanded
        // character's turn, banner or no banner — the strip is the reason the
        // person does not have three chats open.
        commandCenter.record(turn, from: id)
        guard let notice = completionNotice(
            for: turn,
            isChatVisible: character(id)?.isChatVisible ?? false
        ) else { return }

        // Her portrait rides along when she has one. Asked through the Bool and
        // the URL rather than `resolve`, whose `Option` would mean importing
        // FunctionalCore into a file that sits next to SwiftUI.
        let artwork = ProfileArtwork()
        notifier.post(
            notice,
            from: id,
            picture: artwork.hasArtwork(for: id) ? artwork.url(for: id) : nil
        )
    }

    /// A banner was clicked: bring back the character who posted it, with her
    /// chat open — the answer being on screen is the point of the click.
    ///
    /// The two ⌘H sets are cleared for her because she is on the desktop again
    /// whatever they say, and leaving her in them would have Show All believe
    /// it still owes her an appearance.
    private func openFromNotification(_ id: UUID) {
        guard let character = character(id) else { return }
        hiddenByShortcut.remove(id)
        chatsHiddenByShortcut.remove(id)
        character.openChat()
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
            },
            isCommandWindowVisible: commandWindow.isVisible
        )
    }

    /// Applies what a menu row asked for. Every case names the character it is
    /// about, so nothing here has to guess which one the click meant.
    private func perform(_ action: StatusMenuAction) {
        switch action {
        case .toggleCharacter(let id):
            character(id)?.toggleCharacterVisibility()
        case .toggleAllCharacters:
            if characters.contains(where: \.isCharacterVisible) { hideEverything() }
            else { showEverything() }
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
            // From the default profile, not a clone of whoever is focused —
            // the owner asked for that switch in 20.1. What she is called is
            // still `newCharacterDraft`'s decision; adding her to the library
            // brings her window up through `reconcileCharacters`.
            let fresh = newCharacterDraft(
                from: SecretaryProfile(name: defaultNewCharacterName),
                existing: profiles.profiles
            )
            profiles.add(fresh)
            // Her default face is the app icon itself — the icns, whose art
            // `make-icon.swift` has already trimmed and fitted, which is what
            // sits well in the round avatar frame. The raw artwork PNG was
            // tried first and the owner sent it back: its proportions don't
            // fit the character frame (2026-08-19). Read from the bundle
            // file, NOT `applicationIconImage`, which answers with a generic
            // folder when the app runs unbundled (`swift run`, while
            // driving) and put a folder on a character once. No icns — a dev
            // run — means no picture at all: never a wrong face.
            if let icns = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: icns),
               let tiff = icon.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                _ = profiles.setArtwork(pngData: png, for: fresh.id)
            }
            character(fresh.id)?.openChat()
        case .toggleCommandWindow:
            commandWindow.toggle(using: focused.appearance)
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
    /// the rule is `dismissDecision`, and this gathers what it needs.
    ///
    /// - Returns: whether it acted, which the local monitor needs in order to
    ///   decide whether to swallow the keystroke or hand it on.
    @discardableResult
    private func dismissWhateverIsInFront(trigger: DismissTrigger) -> Bool {
        // The command window first, on either path. While it holds the
        // keyboard, Esc typed into it is what the backlog specifies: hide the
        // window, leave the sessions running. Without this rung the hot key —
        // claimed whenever any chat bubble is dismissable — consumes the press
        // and spends it on a chat the person is not even typing in.
        if commandWindow.isKey, commandWindow.isVisible {
            commandWindow.hide()
            return true
        }
        let decision = dismissDecision(
            characters.map {
                DismissCandidate(
                    id: $0.profileID,
                    holdsKeyboard: $0.holdsKeyboard,
                    hasDismissable: $0.hasDismissableWindow,
                    isCharacterVisible: $0.isCharacterVisible
                )
            },
            trigger: trigger
        )
        guard let decision, let character = character(decision.id) else { return false }

        switch decision.step {
        case .dismissWindow: character.dismissFrontmost()
        case .hideCharacter: character.hideCharacter()
        }
        return true
    }

    /// Esc once more, with the chat already closed: she goes away too.
    ///
    /// A *local* monitor, and that is the entire design. Esc could not be added
    /// to the system-wide claim — `GlobalShortcut` is a receipt for what that
    /// costs, and a character is visible nearly all the time, so claiming Esc
    /// while she is on screen is claiming it permanently. Locally, the key only
    /// reaches us when one of our own windows holds the keyboard, which is also
    /// the only situation in which "hide her" is what the person meant.
    ///
    /// It cannot double up with the hot key: `dismissDecision` returns nothing
    /// for a local press while anything is dismissable, so exactly one of the
    /// two paths answers any given press.
    private func watchForDismissKey() {
        dismissKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            return dismissWhateverIsInFront(trigger: .ownWindow) ? nil : event
        }
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
                keyCode: event.keyCode,
                hasOnlyCommand: flags == .command
            ) else { return event }
            self.hideEverything()
            return nil
        }
    }

    /// What ⌘H does: the whole app leaves the screen — every character, every
    /// chat, every pinned pane, Token Usage and About.
    ///
    /// `NSApplication.hide` is not it. An accessory app has no Dock tile to come
    /// back from, and its own panels are `hidesOnDeactivate: false` precisely so
    /// that clicking into another app does not take the companion away — which
    /// leaves this as the one thing that can honestly mean "all of it, now".
    ///
    /// Written as `hide`, never `toggle`: applied to a roster, a toggle brings
    /// back whoever was already away, so ⌘H would have shown a character
    /// instead of hiding one.
    private func hideEverything() {
        hiddenByShortcut = Set(characters.filter(\.isCharacterVisible).map(\.profileID))
        // Taken before they close, because that is the only moment it is
        // knowable — and it is what "bring it all back" has to mean.
        chatsHiddenByShortcut = Set(characters.filter(\.isChatVisible).map(\.profileID))
        // Remembered before the blanket sweep below takes it, or "Show All"
        // could never bring it back — the asymmetry this method's doc warns of.
        commandHiddenByShortcut = commandWindow.isVisible
        characters.forEach { $0.hideEverythingOfHers() }
        usageWindow.close()
        // The About window is AppKit's, opened by
        // `orderFrontStandardAboutPanel`, and there is no handle to it — this
        // sweep is how it goes away, and it also catches anything a later sprint
        // puts on screen without telling this method about it.
        NSApp.windows.filter(\.isVisible).forEach { $0.orderOut(nil) }
    }

    /// The other half of the menu's one row: everybody back on the desktop,
    /// with the chat that was open when they left.
    ///
    /// Symmetric with `hideEverything` on purpose — what went away is what
    /// comes back. Restoring the characters but not the conversation would make
    /// "Show All" a different act from undoing "Hide All", and the bubble that
    /// vanished is usually the reason the menu is being opened again.
    ///
    /// Nothing is opened that was not open. If no chat was showing, none
    /// appears: a window arriving unasked is worse than one that stayed shut.
    private func showEverything() {
        // Anyone the roster gained while everything was away comes back too —
        // a character created behind a hidden desktop must not stay invisible
        // with no row that would reveal her.
        characters.forEach { $0.showCharacter() }
        characters
            .filter { chatsHiddenByShortcut.contains($0.profileID) }
            .forEach { $0.openChat() }
        if commandHiddenByShortcut, let focused { commandWindow.show(using: focused.appearance) }
        hiddenByShortcut = []
        chatsHiddenByShortcut = []
        commandHiddenByShortcut = false
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
        // A kept Claude Code process is not a child that ends when we do —
        // quitting without this leaves one `claude` per character running with
        // nothing attached to them.
        characters.forEach { $0.backend.stopWarmProcess() }
    }

    /// Launching the app again while it is already running.
    ///
    /// macOS does not start a second process — it reactivates this one and
    /// sends this. With the character hidden, nothing at all would appear, and
    /// double-clicking the app again is exactly what someone does when they
    /// can't see it. Hiding is for getting it out of the way for a moment, not
    /// a setting to be remembered, so reopening always brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Exactly who ⌘H took away, since ⌘H can now take away several. Coming
        // back with one character when three went is the kind of asymmetry that
        // reads as a lost character rather than as a shortcut.
        let returning = characters.filter { hiddenByShortcut.contains($0.profileID) }
        (returning.isEmpty ? [focused].compactMap { $0 } : returning).forEach { $0.showCharacter() }
        hiddenByShortcut = []
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
    /// While the command box holds the keyboard the shortcut sizes *that
    /// box's* text — the window is the app's, and growing one character's
    /// bubbles because the caret happened to be here would resize windows the
    /// person is not looking at.
    func increaseTextSize(_ sender: Any?) {
        if commandWindow.isKey { commandCenter.bumpFontSize(1) }
        else { focused?.appearance.increaseFontSize() }
    }

    func decreaseTextSize(_ sender: Any?) {
        if commandWindow.isKey { commandCenter.bumpFontSize(-1) }
        else { focused?.appearance.decreaseFontSize() }
    }

    /// ⌘H. Goes through the same toggle the status bar item uses; the character
    /// reports back so the menu's wording doesn't go stale.
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
            Task { @MainActor in
                self?.backendStatus.availability = availability
                // Asking as soon as there is something to ask: the sign-in
                // check needs the executable, so it cannot run any earlier, and
                // waiting for the panel to be opened would leave the app with
                // no idea whether it can work until somebody looked.
                self?.backendStatus.checkConnection()
            }
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
        if let focused { usageWindow.follow(focused.appearance) }
    }
}
