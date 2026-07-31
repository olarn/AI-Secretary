import AppKit
import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import LLMProvider
import Credentials

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppCommands {
    private let stateMachine = AssistantStateMachine()
    private let chatLayout = ChatBubbleLayout()
    private let registry = ProjectRegistry()
    private let credentials = KeychainCredentialStore()
    /// The API-key path, kept as the fallback for anyone without Claude Code.
    private lazy var apiProvider = ClaudeChatProvider(
        apiKeyProvider: { [credentials] in credentials.apiKeyText }
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
    private var hotKeys: GlobalHotKeys?
    private lazy var usageWindow = UsageWindow(secretary: secretary, appearance: appearance)
    private var isChatVisible = false
    private var isCharacterVisible = true

    /// What the character view asks for at 1×, measured from the view itself
    /// rather than written down here — a hard-coded window that was a few points
    /// too small clipped the halo into a flat edge across the top of the head.
    private var characterBaseSize: CGSize = .zero
    /// The window follows the S/M/L choice; `CharacterView` scales to match.
    private var characterSize: CGSize {
        let factor = appearance.settings.appScale.factor
        return CGSize(
            width: characterBaseSize.width * factor,
            height: characterBaseSize.height * factor
        )
    }
    /// Both axes are the user's now, from Appearance. The tail is positioned
    /// against the width rather than at a fixed offset, so `applyChatLayout`
    /// re-anchors it on every size change and it stays on the character.
    private var chatSize: CGSize {
        CGSize(
            width: appearance.settings.chatWidth,
            height: appearance.settings.chatHeight
        )
    }
    /// Where the tail tip sits along the bubble's edge, taken from the shape
    /// itself so the two can't drift apart. A distance rather than a fraction,
    /// so widening the bubble leaves the tip on the character.
    private var tailTipOffset: CGFloat { SpeechBubbleShape.tailTipOffset }
    /// Gap kept between the bubble and the screen edge when clamping horizontally.
    private let screenMargin: CGFloat = 8
    /// How far the bubble is pushed sideways, away from the character, as a
    /// fraction of **the character's** width — not the bubble's.
    ///
    /// It has to scale with the character or the same offset reads differently at
    /// each size: a fixed 36pt put the tail tip outside a small character
    /// altogether (S looked detached) and well inside a large one (L sat under
    /// the bubble). As a share of the character's width, the tip lands on the
    /// same spot at every size.
    private let bubbleClearanceFraction: CGFloat = 0.28
    /// Gap between the character and the bubble window. The tail tip now ends
    /// exactly at the window edge, and the character's avatar sits ~12pt inside
    /// its own window, so a small negative gap makes the tail visually touch
    /// the avatar. Scaled with the character, since the inset it compensates for
    /// scales too.
    private var characterGap: CGFloat {
        -14 * appearance.settings.appScale.factor
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let characterHost = FirstMouseHostingView(
            rootView: CharacterView(
                machine: stateMachine,
                secretary: secretary,
                profiles: profiles,
                appearance: appearance,
                onTap: { [weak self] in self?.toggleChatPanel() }
            )
        )
        // Ask the view how big it wants to be at 1×, then give it exactly that
        // times the S/M/L factor, so nothing is cropped.
        characterBaseSize = characterHost.fittingSize

        // Wrapped in a plain container rather than used as the content view
        // directly: an NSHostingView publishes its SwiftUI layout size as an
        // intrinsic size, and Auto Layout then shrinks the window back to it.
        // `scaleEffect` doesn't change that layout size, so at L the character
        // was drawn 1.3x inside a 1x window and clipped on every side.
        characterPanel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: characterSize),
            content: Self.container(for: characterHost, size: characterSize)
        )

        let chatHost = FirstMouseHostingView(
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
            onToggleCharacter: { [weak self] in self?.toggleCharacterVisibility() ?? true },
            onShowUsage: { [weak self] in self?.usageWindow.toggle() }
        )

        // Esc is claimed from the whole system, so the bubble answers it while
        // the user is typing in another app. Only Esc, and only while the chat
        // is showing — see `GlobalShortcut` for why ⌘H is not in this list.
        hotKeys = GlobalHotKeys(actions: [
            .closeChat: { [weak self] in self?.hideChatPanel() }
        ])
        hotKeys?.apply(chatVisible: isChatVisible)

        showCharacter()
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
        showCharacter()
        return true
    }

    /// Puts the character on screen and keeps the menu wording honest. Safe
    /// when it is already showing.
    private func showCharacter() {
        isCharacterVisible = true
        characterPanel.orderFrontRegardless()
        statusBar?.setCharacterVisible(true)
    }

    // MARK: - Menu commands

    /// ⌘+ / ⌘−, doing exactly what the +/− buttons in Settings do. Wired here
    /// rather than in the panel because the shortcut has to work whenever the
    /// app is active, including when the chat is closed.
    func increaseTextSize(_ sender: Any?) { appearance.increaseFontSize() }

    func decreaseTextSize(_ sender: Any?) { appearance.decreaseFontSize() }

    /// ⌘H. Goes through the same toggle the status bar item uses, then tells the
    /// menu what happened so its wording doesn't go stale.
    func toggleCharacter(_ sender: Any?) {
        statusBar.setCharacterVisible(toggleCharacterVisibility())
    }

    func showAbout(_ sender: Any?) { AboutPanel.show() }

    func toggleUsageWindow(_ sender: Any?) { usageWindow.toggle() }

    /// Lets the window own its size and the hosted view fill it.
    private static func container(for host: NSView, size: CGSize) -> NSView {
        let container = FirstMouseContainerView(frame: NSRect(origin: .zero, size: size))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        return container
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
            // Only a character that just changed size can have been pushed off
            // an edge by this call. Resizing the chat used to run this too, and
            // a character standing where the user put it — at the bottom of the
            // screen, over the Dock — was yanked 54pt upward the moment the
            // grip moved. Resizing the bubble must resize the bubble and
            // nothing else.
            if characterResized { keepCharacterOnScreen(in: screen) }
            applyChatLayout(in: screen.visibleFrame)
        }
    }

    /// A character that just grew near an edge would otherwise hang off it.
    ///
    /// Measured against the whole screen rather than the part left over by the
    /// Dock and menu bar: standing on top of the Dock is a normal place to put
    /// a desktop character, and having it shoved out of there for growing one
    /// size is the same complaint as being shoved for a resize. The rule is
    /// only "don't end up off the screen".
    private func keepCharacterOnScreen(in screen: NSScreen) {
        let bounds = screen.frame
        let frame = characterPanel.frame
        let x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
        let y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
        if x != frame.minX || y != frame.minY {
            characterPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// Opens the chat, making the character visible first if it was hidden so the
    /// bubble has something to anchor to.
    private func openChatFromMenu() {
        showCharacter()
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
        statusBar?.setCharacterVisible(isCharacterVisible)
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

    /// Repositions the bubble relative to the character's current frame.
    /// The decision itself is `placeBubble`, which can be checked without a
    /// screen; this only feeds it the current frames and applies the answer.
    private func applyChatLayout(in visibleFrame: NSRect) {
        let characterFrame = characterPanel.frame
        let placement = placeBubble(
            character: characterFrame,
            bubble: chatSize,
            visibleFrame: visibleFrame,
            tailTipOffset: tailTipOffset,
            clearance: characterFrame.width * bubbleClearanceFraction,
            gap: characterGap,
            margin: screenMargin
        )

        chatLayout.isMirrored = placement.isMirrored
        chatLayout.isFlippedVertically = placement.isFlippedVertically
        chatPanel.setFrameOrigin(placement.origin)
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
        hotKeys?.apply(chatVisible: true)
        // The display may have changed since launch; re-clamp before showing,
        // against the screen the character is on rather than whichever one
        // happens to be "main" at the time.
        appearance.applyScreenLimits(
            (characterPanel.screen ?? NSScreen.main)?.visibleFrame
        )
        NSApp.activate(ignoringOtherApps: true)
        chatPanel.makeKeyAndOrderFront(nil)
        chatPanel.animator().alphaValue = 1
    }

    private func hideChatPanel() {
        isChatVisible = false
        // Esc goes back to whichever app the user is actually in the moment the
        // bubble is off screen.
        hotKeys?.apply(chatVisible: false)
        chatPanel.animator().alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.chatPanel.orderOut(nil)
        }
    }
}
