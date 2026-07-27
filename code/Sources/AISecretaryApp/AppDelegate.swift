import AppKit
import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import LLMProvider
import Credentials

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stateMachine = AssistantStateMachine()
    private let chatLayout = ChatBubbleLayout()
    private let registry = ProjectRegistry()
    private let credentials = KeychainCredentialStore()
    /// The API-key path, kept as the fallback for anyone without Claude Code.
    private lazy var apiProvider = ClaudeChatProvider(
        apiKeyProvider: { [credentials] in credentials.apiKey() }
    )
    /// Prefers the user's own Claude Code and falls back to the API key.
    private lazy var backend = ChatBackend(fallback: apiProvider)
    private let backendStatus = BackendStatus()
    private let appearance = Appearance()
    private let profiles = ProfileLibrary()
    private lazy var secretary = Secretary(
        stateMachine: stateMachine,
        registry: registry,
        profile: profiles.active,
        chatProvider: backend
    )
    private var characterPanel: FloatingPanel!
    private var chatPanel: FloatingPanel!
    private var statusBar: StatusBarController!
    private var isChatVisible = false
    private var isCharacterVisible = true

    /// The character window follows the S/M/L choice, so this is derived rather
    /// than fixed. `CharacterView` scales its content to match.
    private var characterSize: CGFloat {
        CharacterView.baseSize * appearance.settings.appScale.factor
    }
    /// Width is fixed: the bubble's tail is positioned against it, so letting
    /// the width change would pull the tail away from the character. Height is
    /// the user's, from Appearance.
    private let chatWidth: CGFloat = 360
    private var chatSize: CGSize {
        CGSize(width: chatWidth, height: appearance.settings.chatHeight)
    }
    /// Where the tail tip sits across the bubble's width, taken from the shape
    /// itself so the two can't drift apart.
    private var tailFraction: CGFloat {
        SpeechBubbleShape.tailTipFraction(forWidth: chatSize.width)
    }
    /// Gap kept between the bubble and the screen edge when clamping horizontally.
    private let screenMargin: CGFloat = 8
    /// How far the bubble is pushed sideways, away from the character, as a
    /// fraction of its own width. Lining the tail's tip up with the character's
    /// centre put most of the bubble across the character; this backs it off.
    private let bubbleClearanceFraction: CGFloat = 0.2
    /// Gap between the character and the bubble window. The tail tip now ends
    /// exactly at the window edge, and the character's avatar sits ~12pt inside
    /// its own window, so a small negative gap makes the tail visually touch
    /// the avatar. Scaled with the character, since the inset it compensates for
    /// scales too.
    private var characterGap: CGFloat {
        -14 * appearance.settings.appScale.factor
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let characterHost = NSHostingView(
            rootView: CharacterView(
                machine: stateMachine,
                secretary: secretary,
                profiles: profiles,
                appearance: appearance,
                onTap: { [weak self] in self?.toggleChatPanel() }
            )
        )
        characterHost.frame = NSRect(x: 0, y: 0, width: characterSize, height: characterSize)

        characterPanel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: characterSize, height: characterSize),
            content: characterHost
        )

        let chatHost = NSHostingView(
            rootView: ChatPanelView(
                machine: stateMachine,
                secretary: secretary,
                registry: registry,
                credentials: credentials,
                backendStatus: backendStatus,
                appearance: appearance,
                profiles: profiles,
                layout: chatLayout,
                onClose: { [weak self] in self?.hideChatPanel() }
            )
        )
        chatHost.frame = NSRect(origin: .zero, size: chatSize)

        chatPanel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: chatSize),
            content: chatHost
        )
        chatPanel.alphaValue = 0

        positionInitialWindows()
        observeWindowMovement()
        detectBackend()

        // Resizing an NSPanel is imperative work, so the model calls back here
        // rather than the delegate re-deriving it during a view update.
        appearance.onChange = { [weak self] in self?.applyWindowSizes() }
        // Switching profile has to reach the prompt as well as the pictures.
        profiles.onActiveChange = { [weak self] profile in
            self?.secretary.apply(profile: profile)
        }

        statusBar = StatusBarController(
            onOpenChat: { [weak self] in self?.openChatFromMenu() },
            onToggleCharacter: { [weak self] in self?.toggleCharacterVisibility() ?? true }
        )

        characterPanel.orderFrontRegardless()
    }

    /// Finds Claude Code off the main thread. The fast path is a handful of
    /// `stat` calls, but the fallback launches the user's login shell, which can
    /// take seconds — doing that here would delay the character appearing.
    private func detectBackend() {
        backend.observeAvailability { [weak self] availability in
            Task { @MainActor in self?.backendStatus.availability = availability }
        }
        let backend = self.backend
        Task.detached(priority: .utility) { backend.resolve() }
    }

    /// Resizes both windows to the current choices and re-anchors the bubble,
    /// keeping the tail on the character and the whole panel on screen.
    ///
    /// The character grows from its bottom-centre: it usually sits near the Dock
    /// with the bubble above it, and growing from the top-left corner instead
    /// would walk it across the desktop each time the size changed.
    private func applyWindowSizes() {
        let old = characterPanel.frame
        let size = characterSize
        if old.width != size {
            characterPanel.setFrame(
                NSRect(
                    x: old.midX - size / 2,
                    y: old.minY,
                    width: size,
                    height: size
                ),
                display: true
            )
        }

        var frame = chatPanel.frame
        frame.size = chatSize
        chatPanel.setFrame(frame, display: true)

        if let screen = characterPanel.screen ?? NSScreen.main {
            keepCharacterOnScreen(in: screen.visibleFrame)
            applyChatLayout(in: screen.visibleFrame)
        }
    }

    /// A character that just grew near an edge would otherwise hang off it.
    private func keepCharacterOnScreen(in visibleFrame: NSRect) {
        let frame = characterPanel.frame
        let x = min(
            max(frame.minX, visibleFrame.minX),
            visibleFrame.maxX - frame.width
        )
        let y = min(
            max(frame.minY, visibleFrame.minY),
            visibleFrame.maxY - frame.height
        )
        if x != frame.minX || y != frame.minY {
            characterPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// Opens the chat, making the character visible first if it was hidden so the
    /// bubble has something to anchor to.
    private func openChatFromMenu() {
        if !isCharacterVisible { _ = toggleCharacterVisibility() }
        showChatPanel()
    }

    /// Shows or hides the floating character. Returns the new visibility so the
    /// menu can relabel its item. Hiding the character also hides the chat.
    @discardableResult
    private func toggleCharacterVisibility() -> Bool {
        isCharacterVisible.toggle()
        if isCharacterVisible {
            characterPanel.orderFrontRegardless()
        } else {
            if isChatVisible { hideChatPanel() }
            characterPanel.orderOut(nil)
        }
        return isCharacterVisible
    }

    private func positionInitialWindows() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let characterOrigin = NSPoint(
            x: visibleFrame.maxX - 160,
            y: visibleFrame.minY + 120
        )
        characterPanel.setFrameOrigin(characterOrigin)

        applyChatLayout(in: visibleFrame)
    }

    private func observeWindowMovement() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: characterPanel,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so it's safe to assert main-actor
            // isolation to reach the panel and layout without a warning.
            MainActor.assumeIsolated {
                guard let self, let screen = self.characterPanel.screen ?? NSScreen.main else { return }
                self.applyChatLayout(in: screen.visibleFrame)
            }
        }
    }

    /// Clamps a coordinate into a range, tolerating an inverted one: a window
    /// taller than the screen has no valid origin, and the top edge is the less
    /// bad end to lose.
    private func clamped(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }

    /// Repositions the bubble relative to the character's current frame.
    /// Flips horizontally (mirroring the tail) if the natural placement
    /// would run off the left/right screen edge, and flips vertically
    /// (bubble below instead of above, tail pointing up) if placing it
    /// above the character would run off the top of the screen.
    private func applyChatLayout(in visibleFrame: NSRect) {
        let characterFrame = characterPanel.frame
        let characterCenterX = characterFrame.midX

        // Pushed sideways away from the character, so the bubble sits beside it
        // rather than across it. Whichever side it's on, the shift is outward:
        // right when the bubble is to the character's right, left when mirrored.
        let clearance = chatSize.width * bubbleClearanceFraction
        let naturalX = characterCenterX - chatSize.width * tailFraction + clearance
        let mirrored = naturalX + chatSize.width > visibleFrame.maxX - screenMargin
        var originX = mirrored
            ? characterCenterX - chatSize.width * (1 - tailFraction) - clearance
            : naturalX
        originX = clamped(
            originX,
            min: visibleFrame.minX + screenMargin,
            max: visibleFrame.maxX - chatSize.width - screenMargin
        )

        let aboveY = characterFrame.minY + characterFrame.height + characterGap
        let flippedVertically = aboveY + chatSize.height > visibleFrame.maxY - screenMargin
        // Clamped like the horizontal axis, and for the same reason. A tall
        // panel — one with a settings section open — doesn't fit above the
        // character, and flipping it below a character that sits near the Dock
        // put the whole window off the bottom of the screen: the app looked like
        // it had vanished. Staying on screen wins over the tail's ideal side.
        let originY = clamped(
            flippedVertically ? characterFrame.minY - chatSize.height - characterGap : aboveY,
            min: visibleFrame.minY + screenMargin,
            max: visibleFrame.maxY - chatSize.height - screenMargin
        )

        chatLayout.isMirrored = mirrored
        chatLayout.isFlippedVertically = flippedVertically
        chatPanel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func toggleChatPanel() {
        if isChatVisible {
            hideChatPanel()
        } else {
            showChatPanel()
        }
    }

    private func showChatPanel() {
        isChatVisible = true
        // The display may have changed since launch; re-clamp before showing.
        appearance.refreshScreenLimit()
        NSApp.activate(ignoringOtherApps: true)
        chatPanel.makeKeyAndOrderFront(nil)
        chatPanel.animator().alphaValue = 1
    }

    private func hideChatPanel() {
        isChatVisible = false
        chatPanel.animator().alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.chatPanel.orderOut(nil)
        }
    }
}
