import AppKit
import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import LLMProvider

@MainActor
final class CharacterInstance {
    let profileID: UUID

    let stateMachine = AssistantStateMachine()
    let chatLayout = ChatBubbleLayout()
    let backend: ChatBackend
    let secretary: Secretary
    let infoWindows: InfoWindows

    let appearance: Appearance
    private let profiles: ProfileLibrary
    private let registry: ProjectRegistry
    private let backendStatus: BackendStatus
    private let vendorStatus: VendorStatus

    private(set) var characterPanel: FloatingPanel!
    private(set) var chatPanel: FloatingPanel!

    private(set) var isChatVisible = false
    private(set) var isCharacterVisible = true

    var onDismissableChanged: (() -> Void)?

    var onUsed: (() -> Void)?

    private var characterBaseSize: CGSize = .zero

    private var characterSize: CGSize {
        let factor = appearance.settings.characterScale.factor
        return CGSize(
            width: characterBaseSize.width * factor,
            height: characterBaseSize.height * factor
        )
    }

    private var chatSize: CGSize {
        CGSize(
            width: appearance.settings.chatWidth,
            height: appearance.settings.chatHeight
        )
    }

    private var tailTipOffset: CGFloat { SpeechBubbleShape.tailTipOffset }
    private let bubbleClearanceFraction: CGFloat = 0.28
    private var characterGap: CGFloat {
        -14 * appearance.settings.characterScale.factor
    }

    init(
        profileID: UUID,
        profiles: ProfileLibrary,
        appearance: Appearance,
        registry: ProjectRegistry,
        backendStatus: BackendStatus,
        detector: ClaudeCodeDetector,
        conversationStore: ConversationStoring,
        attachmentStore: AttachmentStaging
    ) {
        self.profileID = profileID
        self.profiles = profiles
        self.appearance = appearance
        self.registry = registry
        self.backendStatus = backendStatus
        let backend = ChatBackend(detector: detector)
        self.backend = backend
        self.infoWindows = InfoWindows(appearance: appearance)
        self.secretary = Secretary(
            stateMachine: stateMachine,
            registry: registry,
            profile: profiles.profiles.first { $0.id == profileID } ?? profiles.active,
            chatProvider: backend,
            conversationStore: conversationStore,
            attachmentStore: attachmentStore,
            grantStore: FileStandingGrantStore(
                fileURL: FileStandingGrantStore.url(forCharacter: profileID)
            ),
            choiceStore: UserDefaultsAssistantChoiceStore(character: profileID)
        )
        let secretary = self.secretary
        self.vendorStatus = VendorStatus(
            store: UserDefaultsVendorChoiceStore(character: profileID),
            backend: backend,
            claudeAvailability: { [weak backendStatus] in backendStatus?.availability },
            chosenModel: { [weak secretary] in secretary?.chosenModel },
            chooseModel: { [weak secretary] chosen in secretary?.chooseModel(chosen) },
            turnInFlight: { [weak secretary] in secretary?.stateMachine.state.isBusy ?? false },
            workingDirectory: { [weak secretary] in secretary?.workingDirectory }
        )
    }

    private var moveObserver: NSObjectProtocol?

    func buildWindows(ordinal: Int, onClose: @escaping () -> Void) {
        let characterHost = FirstMouseHostingView(
            rootView: CharacterView(
                machine: stateMachine,
                secretary: secretary,
                profiles: profiles,
                profileID: profileID,
                appearance: appearance,
                onTap: { [weak self] in self?.toggleChatPanel() }
            )
        )
        characterBaseSize = characterHost.fittingSize

        characterPanel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: characterSize),
            content: Self.container(for: characterHost, size: characterSize)
        )

        let chatHost = FirstMouseHostingView(
            rootView: ChatPanelView(
                machine: stateMachine,
                secretary: secretary,
                registry: registry,
                backendStatus: backendStatus,
                vendorStatus: vendorStatus,
                appearance: appearance,
                profiles: profiles,
                profileID: profileID,
                layout: chatLayout,
                onClose: onClose,
                onPin: { [weak self] spec in self?.infoWindows.open(spec) }
            )
        )
        chatHost.frame = NSRect(origin: .zero, size: chatSize)

        chatPanel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: chatSize),
            content: chatHost,
            takesKeyOnClick: true
        )
        chatPanel.alphaValue = 0
        applyChatShadow()

        secretary.onPinWindow = { [weak self] spec in self?.infoWindows.open(spec) }
        infoWindows.onVisibilityChanged = { [weak self] in self?.onDismissableChanged?() }

        positionInitialWindows(ordinal: ordinal)
        observeWindowMovement()
    }

    func tearDown() {
        backend.stopWarmProcess()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        infoWindows.clearAll()
        chatPanel?.orderOut(nil)
        characterPanel?.orderOut(nil)
        isChatVisible = false
        isCharacterVisible = false
        onDismissableChanged?()
    }

    private static func container(for host: NSView, size: CGSize) -> NSView {
        let container = FirstMouseContainerView(frame: NSRect(origin: .zero, size: size))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        return container
    }

    private func positionInitialWindows(ordinal: Int) {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let characterOrigin = savedCharacterOrigin(
            saved: UserDefaults.standard.string(forKey: characterOriginKey(profileID)),
            size: characterPanel.frame.size,
            screenFrame: screen.frame
        ) ?? CharacterLaunch.origin(
            ordinal: ordinal,
            characterSize: characterPanel.frame.size,
            visibleFrame: visibleFrame,
            screenFrame: screen.frame
        )
        characterPanel.setFrameOrigin(NSPoint(x: characterOrigin.x, y: characterOrigin.y))

        applyChatLayout(in: visibleFrame)
    }

    private func observeWindowMovement() {
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: characterPanel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let screen = self.characterPanel.screen ?? NSScreen.main else { return }
                UserDefaults.standard.set(
                    characterOriginString(self.characterPanel.frame.origin),
                    forKey: characterOriginKey(self.profileID)
                )
                self.applyChatLayout(in: screen.visibleFrame)
            }
        }
    }

    private func applyChatLayout(in visibleFrame: NSRect) {
        let characterFrame = characterPanel.frame
        let placement = placeBubble(
            character: characterFrame,
            bubble: chatSize,
            visibleFrame: visibleFrame,
            tailTipOffset: tailTipOffset,
            clearance: characterFrame.width * bubbleClearanceFraction,
            gap: characterGap,
            margin: bubbleScreenMargin
        )

        chatLayout.isMirrored = placement.isMirrored
        chatLayout.isFlippedVertically = placement.isFlippedVertically
        chatPanel.setFrameOrigin(placement.origin)
    }

    func applyWindowSizes() {
        applyChatShadow()
        let old = characterPanel.frame
        let size = characterSize
        let characterResized = old.size != size
        if characterResized {
            characterPanel.setFrame(
                NSRect(
                    x: old.midX - size.width / 2,
                    y: old.minY,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }

        var frame = chatPanel.frame
        frame.size = chatSize
        chatPanel.setFrame(frame, display: true)

        if let screen = characterPanel.screen ?? NSScreen.main {
            if characterResized { keepCharacterOnScreen(in: screen) }
            applyChatLayout(in: screen.visibleFrame)
        }
    }

    private func keepCharacterOnScreen(in screen: NSScreen) {
        let bounds = screen.frame
        let frame = characterPanel.frame
        let x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
        let y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
        if x != frame.minX || y != frame.minY {
            characterPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func applyChatShadow() {
        let wantsShadow = !appearance.settings.liquidGlass
        guard let chatPanel, chatPanel.hasShadow != wantsShadow else { return }
        chatPanel.hasShadow = wantsShadow
        chatPanel.invalidateShadow()
    }

    func applyControlAppearance(_ controls: NSAppearance?) {
        characterPanel?.appearance = controls
        chatPanel?.appearance = controls
        infoWindows.applyControlAppearance(controls)
    }

    func applyOwnControlAppearance() {
        applyControlAppearance(appearance.colors.controlAppearance)
    }

    var hasDismissableWindow: Bool {
        hasSomethingToDismiss(
            isChatVisible: isChatVisible,
            visiblePanes: infoWindows.visiblePaneCount
        )
    }

    var holdsKeyboard: Bool {
        guard let key = NSApp.keyWindow else { return false }
        return key === chatPanel || key === characterPanel || infoWindows.holds(key)
    }

    func showCharacter() {
        isCharacterVisible = true
        characterPanel.orderFrontRegardless()
    }

    func hideCharacter() {
        isCharacterVisible = false
        if isChatVisible { hideChatPanel() }
        characterPanel.orderOut(nil)
    }

    func hideEverythingOfHers() {
        infoWindows.hideAll()
        hideCharacter()
    }

    @discardableResult
    func toggleCharacterVisibility() -> Bool {
        if isCharacterVisible {
            hideCharacter()
        } else {
            showCharacter()
        }
        return isCharacterVisible
    }

    func toggleChatPanel() {
        if isChatVisible {
            hideChatPanel()
        } else {
            showChatPanel()
        }
    }

    func openChat() {
        showCharacter()
        showChatPanel()
    }

    func showChatPanel() {
        isChatVisible = true
        onDismissableChanged?()
        onUsed?()
        appearance.applyScreenLimits(
            (characterPanel.screen ?? NSScreen.main)?.visibleFrame
        )
        NSApp.activate(ignoringOtherApps: true)
        chatPanel.makeKeyAndOrderFront(nil)
        chatPanel.animator().alphaValue = 1
        chatLayout.requestInputFocus()
    }

    func hideChatPanel() {
        isChatVisible = false
        if isCharacterVisible, chatPanel.isKeyWindow { characterPanel.makeKey() }
        onDismissableChanged?()
        chatPanel.animator().alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.chatPanel.orderOut(nil)
        }
    }

    func dismissFrontmost() {
        if infoWindows.hideKeyWindow() { return }
        if isChatVisible {
            hideChatPanel()
            return
        }
        infoWindows.hideFrontmostVisible()
    }
}
