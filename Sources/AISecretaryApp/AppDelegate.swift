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
    private lazy var chatProvider = ClaudeChatProvider(
        apiKeyProvider: { [credentials] in credentials.apiKey() }
    )
    private lazy var secretary = Secretary(
        stateMachine: stateMachine,
        registry: registry,
        chatProvider: chatProvider
    )
    private var characterPanel: FloatingPanel!
    private var chatPanel: FloatingPanel!
    private var statusBar: StatusBarController!
    private var isChatVisible = false
    private var isCharacterVisible = true

    private let characterSize: CGFloat = 120
    private let chatSize = CGSize(width: 360, height: 520)
    /// Where the tail tip sits across the bubble's width, taken from the shape
    /// itself so the two can't drift apart.
    private var tailFraction: CGFloat {
        SpeechBubbleShape.tailTipFraction(forWidth: chatSize.width)
    }
    /// Gap kept between the bubble and the screen edge when clamping horizontally.
    private let screenMargin: CGFloat = 8
    /// Gap between the character and the bubble window. The tail tip now ends
    /// exactly at the window edge, and the character's avatar sits ~12pt inside
    /// its own window, so a small negative gap makes the tail visually touch
    /// the avatar.
    private let characterGap: CGFloat = -14

    func applicationDidFinishLaunching(_ notification: Notification) {
        let characterHost = NSHostingView(
            rootView: CharacterView(machine: stateMachine, onTap: { [weak self] in
                self?.toggleChatPanel()
            })
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

        statusBar = StatusBarController(
            onOpenChat: { [weak self] in self?.openChatFromMenu() },
            onToggleCharacter: { [weak self] in self?.toggleCharacterVisibility() ?? true }
        )

        characterPanel.orderFrontRegardless()
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
            guard let self, let screen = self.characterPanel.screen ?? NSScreen.main else { return }
            self.applyChatLayout(in: screen.visibleFrame)
        }
    }

    /// Repositions the bubble relative to the character's current frame.
    /// Flips horizontally (mirroring the tail) if the natural placement
    /// would run off the left/right screen edge, and flips vertically
    /// (bubble below instead of above, tail pointing up) if placing it
    /// above the character would run off the top of the screen.
    private func applyChatLayout(in visibleFrame: NSRect) {
        let characterFrame = characterPanel.frame
        let characterCenterX = characterFrame.midX

        let naturalX = characterCenterX - chatSize.width * tailFraction
        let mirrored = naturalX + chatSize.width > visibleFrame.maxX - screenMargin
        var originX = mirrored
            ? characterCenterX - chatSize.width * (1 - tailFraction)
            : naturalX
        originX = min(
            max(originX, visibleFrame.minX + screenMargin),
            visibleFrame.maxX - chatSize.width - screenMargin
        )

        let aboveY = characterFrame.minY + characterFrame.height + characterGap
        let flippedVertically = aboveY + chatSize.height > visibleFrame.maxY - screenMargin
        let originY = flippedVertically
            ? characterFrame.minY - chatSize.height - characterGap
            : aboveY

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
