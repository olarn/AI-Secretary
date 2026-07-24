import AppKit
import SwiftUI
import AssistantState

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stateMachine = AssistantStateMachine()
    private let chatLayout = ChatBubbleLayout()
    private var characterPanel: FloatingPanel!
    private var chatPanel: FloatingPanel!
    private var isChatVisible = false

    private let characterSize: CGFloat = 120
    private let chatSize = CGSize(width: 340, height: 460)
    /// Fraction of the bubble's width where the tail sits before mirroring.
    private let tailFraction: CGFloat = 0.22
    private let screenMargin: CGFloat = 8

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
            rootView: ChatPanelView(machine: stateMachine, layout: chatLayout, onClose: { [weak self] in
                self?.hideChatPanel()
            })
        )
        chatHost.frame = NSRect(origin: .zero, size: chatSize)

        chatPanel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: chatSize),
            content: chatHost
        )
        chatPanel.alphaValue = 0

        positionInitialWindows()
        observeWindowMovement()

        characterPanel.orderFrontRegardless()
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

    /// Repositions the bubble relative to the character's current frame,
    /// flipping to the opposite side (mirroring the tail) whenever the
    /// natural placement would run off the visible screen edge.
    private func applyChatLayout(in visibleFrame: NSRect) {
        let characterFrame = characterPanel.frame
        let characterCenterX = characterFrame.midX

        let naturalX = characterCenterX - chatSize.width * tailFraction
        let wouldOverflowRight = naturalX + chatSize.width > visibleFrame.maxX - screenMargin

        let mirrored = wouldOverflowRight
        var originX = mirrored
            ? characterCenterX - chatSize.width * (1 - tailFraction)
            : naturalX
        originX = min(
            max(originX, visibleFrame.minX + screenMargin),
            visibleFrame.maxX - chatSize.width - screenMargin
        )

        let originY = characterFrame.minY + characterFrame.height + screenMargin

        chatLayout.isMirrored = mirrored
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
