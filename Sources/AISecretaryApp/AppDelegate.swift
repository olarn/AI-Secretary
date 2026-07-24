import AppKit
import SwiftUI
import AssistantState

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stateMachine = AssistantStateMachine()
    private var characterPanel: FloatingPanel!
    private var chatPanel: FloatingPanel!
    private var isChatVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let characterHost = NSHostingView(
            rootView: CharacterView(machine: stateMachine, onTap: { [weak self] in
                self?.toggleChatPanel()
            })
        )
        characterHost.frame = NSRect(x: 0, y: 0, width: 120, height: 120)

        characterPanel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            content: characterHost
        )

        let chatHost = NSHostingView(rootView: ChatPanelView(machine: stateMachine))
        chatHost.frame = NSRect(x: 0, y: 0, width: 340, height: 420)

        chatPanel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            content: chatHost
        )
        chatPanel.alphaValue = 0

        positionInitialWindows()

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

        let chatOrigin = NSPoint(
            x: characterOrigin.x - 360,
            y: characterOrigin.y
        )
        chatPanel.setFrameOrigin(chatOrigin)
    }

    private func toggleChatPanel() {
        isChatVisible.toggle()
        if isChatVisible {
            chatPanel.orderFrontRegardless()
            chatPanel.animator().alphaValue = 1
        } else {
            chatPanel.animator().alphaValue = 0
        }
    }
}
