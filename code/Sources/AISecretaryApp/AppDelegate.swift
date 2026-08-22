import AppKit
import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import LLMProvider

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppCommands {
    private let backendStatus = BackendStatus()
    private let profiles = ProfileLibrary()
    private let detector = ClaudeCodeDetector()

    private var characters: [CharacterInstance] = []
    private var focused: CharacterInstance! {
        lastUsed.flatMap(character) ?? characters.first
    }
    private var lastUsed: UUID?

    private lazy var bus = CharacterBus(roster: { [weak self] in self?.characters ?? [] })

    private lazy var notifier = CompletionNotifier(
        onOpen: { [weak self] id in self?.openFromNotification(id) }
    )

    private var statusBar: StatusBarController!
    private var hotKeys: GlobalHotKeys?
    private var hideKeyMonitor: Any?
    private var dismissKeyMonitor: Any?
    private var hiddenByShortcut: Set<UUID> = []
    private var chatsHiddenByShortcut: Set<UUID> = []
    private var commandHiddenByShortcut = false

    private lazy var commandCenter = CommandCenter(
        roster: { [weak self] in (self?.characters ?? []).map(\.card) },
        deliver: { [weak self] id, text, files in
            guard let secretary = self?.character(id)?.secretary else { return }
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
    private lazy var commandWindow = CommandWindowController(model: commandCenter)

    private let usageRoster = UsageRoster()
    private lazy var usageWindow = UsageWindow(
        roster: usageRoster,
        backend: focused.backend
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        reconcileCharacters()
        profiles.onRosterChange = { [weak self] in self?.reconcileCharacters() }

        notifier.start()

        detectBackend()

        applyControlAppearance()
        profiles.onProfileChange = { [weak self] profile in
            self?.character(profile.id)?.secretary.apply(profile: profile)
        }

        statusBar = StatusBarController(
            menu: { [weak self] in self?.menuState() ?? [] },
            perform: { [weak self] action in self?.perform(action) }
        )

        hotKeys = GlobalHotKeys(actions: [
            .closeChat: { [weak self] in self?.dismissWhateverIsInFront(trigger: .hotKey) }
        ])
        refreshHotKeyClaim()
        watchForHideShortcut()
        watchForDismissKey()

        characters.forEach { $0.showCharacter() }
    }

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
            conversationStore: FileConversationStore(fileURL: historyFile(for: id)),
            attachmentStore: FileAttachmentStore()
        )
        character.onDismissableChanged = { [weak self] in self?.refreshHotKeyClaim() }
        character.secretary.directorySnapshot = { [weak self] in
            self?.bus.directory(excluding: id) ?? []
        }
        character.secretary.onSend = { [weak self] message in self?.bus.deliver(message) }
        character.secretary.onTurnFinished = { [weak self] turn in self?.announce(turn, from: id) }
        character.secretary.onApprovalAsked = { [weak self] asked in
            self?.commandCenter.record(asked, from: id)
        }
        character.secretary.onApprovalSettled = { [weak self] in
            self?.commandCenter.approvalSettled(for: id)
        }
        character.onUsed = { [weak self] in
            guard self?.lastUsed != id else { return }
            self?.lastUsed = id
            self?.applyControlAppearance()
        }
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

    private func historyFile(for id: UUID) -> URL {
        _ = FileConversationStore.adoptLegacyHistory(for: id)
        return FileConversationStore.url(forCharacter: id)
    }

    private func projectsFile(for id: UUID) -> URL {
        _ = FileProjectStore.adoptLegacyProjects(for: id)
        return FileProjectStore.url(forCharacter: id)
    }

    private func announce(_ turn: FinishedTurn, from id: UUID) {
        commandCenter.record(turn, from: id)
        guard let notice = completionNotice(
            for: turn,
            isChatVisible: character(id)?.isChatVisible ?? false
        ) else { return }

        let artwork = ProfileArtwork()
        notifier.post(
            notice,
            from: id,
            picture: artwork.hasArtwork(for: id) ? artwork.url(for: id) : nil
        )
    }

    private func openFromNotification(_ id: UUID) {
        guard let character = character(id) else { return }
        hiddenByShortcut.remove(id)
        chatsHiddenByShortcut.remove(id)
        character.openChat()
    }

    private func menuState() -> [StatusMenuEntry] {
        statusBarMenu(
            summary: AppInfo.statusMenuHeader,
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
            character.openChat()
        case .resumeConversation(let id, let conversation):
            guard let character = character(id) else { return }
            character.secretary.resumeConversation(conversation)
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
            let fresh = newCharacterDraft(
                from: SecretaryProfile(name: defaultNewCharacterName),
                existing: profiles.profiles
            )
            profiles.add(fresh)
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

    @discardableResult
    private func dismissWhateverIsInFront(trigger: DismissTrigger) -> Bool {
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

    private func watchForDismissKey() {
        dismissKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            return dismissWhateverIsInFront(trigger: .ownWindow) ? nil : event
        }
    }

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

    private func hideEverything() {
        hiddenByShortcut = Set(characters.filter(\.isCharacterVisible).map(\.profileID))
        chatsHiddenByShortcut = Set(characters.filter(\.isChatVisible).map(\.profileID))
        commandHiddenByShortcut = commandWindow.isVisible
        characters.forEach { $0.hideEverythingOfHers() }
        usageWindow.close()
        NSApp.windows.filter(\.isVisible).forEach { $0.orderOut(nil) }
    }

    private func showEverything() {
        characters.forEach { $0.showCharacter() }
        characters
            .filter { chatsHiddenByShortcut.contains($0.profileID) }
            .forEach { $0.openChat() }
        if commandHiddenByShortcut, let focused { commandWindow.show(using: focused.appearance) }
        hiddenByShortcut = []
        chatsHiddenByShortcut = []
        commandHiddenByShortcut = false
    }

    func refreshHotKeyClaim() {
        hotKeys?.apply(hasDismissableWindow: characters.contains(where: \.hasDismissableWindow))
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys?.releaseAll()
        characters.forEach { $0.backend.stopWarmProcess() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let returning = characters.filter { hiddenByShortcut.contains($0.profileID) }
        (returning.isEmpty ? [focused].compactMap { $0 } : returning).forEach { $0.showCharacter() }
        hiddenByShortcut = []
        return true
    }

    func increaseTextSize(_ sender: Any?) {
        if commandWindow.isKey { commandCenter.bumpFontSize(1) }
        else { focused?.appearance.increaseFontSize() }
    }

    func decreaseTextSize(_ sender: Any?) {
        if commandWindow.isKey { commandCenter.bumpFontSize(-1) }
        else { focused?.appearance.decreaseFontSize() }
    }

    func showAbout(_ sender: Any?) { AboutPanel.show() }

    func toggleUsageWindow(_ sender: Any?) { usageWindow.toggle(using: focused.appearance) }

    private func detectBackend() {
        detector.observe { [weak self] availability in
            Task { @MainActor in
                self?.backendStatus.availability = availability
                self?.backendStatus.checkConnection()
            }
        }
        let detector = self.detector
        Task.detached(priority: .utility) { detector.resolveOffTheMainThread() }
    }

    private func applyControlAppearance() {
        characters.forEach { $0.applyOwnControlAppearance() }
        if let focused { usageWindow.follow(focused.appearance) }
    }
}
