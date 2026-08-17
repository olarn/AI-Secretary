import AppKit
import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import LLMProvider

/// One character on the desktop, and everything that belongs to her alone.
///
/// This type exists to be multiplied. Until now each of these was a single
/// property on `AppDelegate` — one state machine, one Secretary, one pair of
/// windows, one Claude Code session — which made "add a second character" mean
/// editing the same forty lines twice. Gathering them here first means the
/// second character is a second `CharacterInstance`, not a second copy of the
/// delegate's body.
///
/// What stays outside is what is genuinely the app's rather than hers: the
/// theme and text size, the roster of profiles, the project registry, the
/// status bar item, and the Esc claim, which the whole system can only grant
/// once.
@MainActor
final class CharacterInstance {
    /// Which profile she is. The profile itself lives in the shared
    /// `ProfileLibrary`; this is the key, so two instances can never disagree
    /// about who they are.
    let profileID: UUID

    let stateMachine = AssistantStateMachine()
    let chatLayout = ChatBubbleLayout()
    let backend: ChatBackend
    let secretary: Secretary
    let infoWindows: InfoWindows

    /// Hers since 13-1. Not private: the app-wide windows have no look of their
    /// own and borrow the focused character's.
    let appearance: Appearance
    private let profiles: ProfileLibrary
    /// Hers since 13-1, and the file behind it is hers too. Held so
    /// `buildWindows` can hand the panel the same instance the Secretary was
    /// given.
    private let registry: ProjectRegistry
    private let backendStatus: BackendStatus

    private(set) var characterPanel: FloatingPanel!
    private(set) var chatPanel: FloatingPanel!

    private(set) var isChatVisible = false
    private(set) var isCharacterVisible = true

    /// Told when this character gains or loses something Esc could dismiss.
    /// The claim is system-wide and singular, so the decision is not hers to
    /// make — she only reports that her answer changed.
    var onDismissableChanged: (() -> Void)?

    /// Told when this character is the one being worked with. Token Usage,
    /// About and the ⌘+/⌘− shortcuts have no character of their own and follow
    /// whoever this last named.
    var onUsed: (() -> Void)?

    /// What the character view asks for at 1×, measured from the view itself
    /// rather than written down here — a hard-coded window that was a few points
    /// too small clipped the halo into a flat edge across the top of the head.
    private var characterBaseSize: CGSize = .zero

    /// The window follows the S/M/L choice; `CharacterView` scales to match.
    private var characterSize: CGSize {
        let factor = appearance.settings.characterScale.factor
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
        // Her own session over the app's one search — see `ClaudeCodeDetector`.
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
            // Hers, keyed by profile like every other per-character file. Built
            // here rather than defaulted in `Secretary`, whose default reaches
            // nowhere on purpose — a suite that forgot to override it would
            // otherwise be granting permissions in the person's own name.
            grantStore: FileStandingGrantStore(
                fileURL: FileStandingGrantStore.url(forCharacter: profileID)
            )
        )
    }

    // MARK: - Windows

    /// Kept so it can be taken off again. Left on, an observer for a window
    /// that has gone still fires — which did not matter while there was one
    /// character for the life of the process and does the moment characters can
    /// be deleted.
    private var moveObserver: NSObjectProtocol?

    /// Builds both windows and puts them where they go. Separate from `init`
    /// because it reaches for the screen, and because the callbacks it installs
    /// point back at whoever owns this instance.
    ///
    /// - Parameter ordinal: how many characters were already on the desktop, so
    ///   she stands clear of them rather than exactly on top.
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
                backendStatus: backendStatus,
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
            // The chat is where the keyboard belongs once you click into it —
            // typing, Esc, the arrow keys and ⌘H all read as "to the chat".
            // The character isn't: clicking it opens or closes this panel, and
            // taking the keyboard from the app behind to do that would be rude.
            takesKeyOnClick: true
        )
        chatPanel.alphaValue = 0

        // A reply can ask for part of itself to be kept on screen.
        secretary.onPinWindow = { [weak self] spec in self?.infoWindows.open(spec) }
        infoWindows.onCountChanged = { [weak self] in self?.onDismissableChanged?() }

        positionInitialWindows(ordinal: ordinal)
        observeWindowMovement()
    }

    /// Takes her off the desktop for good. Both windows, her pinned panes, and
    /// the observer that would otherwise outlive them.
    func tearDown() {
        // Her Claude Code process outlives the turn now, so it has to be ended
        // deliberately — nothing else will. A deleted character that left one
        // running would be an invisible process nobody could account for.
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

    /// Lets the window own its size and the hosted view fill it.
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

        let characterOrigin = CharacterLaunch.origin(
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
            margin: bubbleScreenMargin
        )

        chatLayout.isMirrored = placement.isMirrored
        chatLayout.isFlippedVertically = placement.isFlippedVertically
        chatPanel.setFrameOrigin(placement.origin)
    }

    /// Resizes both windows to the current choices and re-anchors the bubble,
    /// keeping the tail on the character and the whole panel on screen.
    ///
    /// The character grows from its bottom-centre: it usually sits near the Dock
    /// with the bubble above it, and growing from the top-left corner instead
    /// would walk it across the desktop each time the size changed.
    func applyWindowSizes() {
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

    /// Tells AppKit which way this character's windows are lit.
    ///
    /// A window property, not something a SwiftUI body can return, and it has
    /// to be re-applied rather than set once: without it the caret, the
    /// scroller and the text-selection tint keep coming from the system's
    /// light/dark setting — a white scroll bar down the side of a dark panel
    /// the moment the theme is overridden.
    func applyControlAppearance(_ controls: NSAppearance?) {
        characterPanel?.appearance = controls
        chatPanel?.appearance = controls
        infoWindows.applyControlAppearance(controls)
    }

    /// The same, from her own theme. Her windows are lit by her settings now,
    /// so nobody outside has to know which they are.
    func applyOwnControlAppearance() {
        applyControlAppearance(appearance.colors.controlAppearance)
    }

    // MARK: - Visibility

    /// Anything Esc would put away for this character.
    var hasDismissableWindow: Bool { isChatVisible || !infoWindows.set.isEmpty }

    /// Whether one of her windows is the one being typed in. What makes Esc
    /// hers rather than another character's.
    var holdsKeyboard: Bool {
        guard let key = NSApp.keyWindow else { return false }
        return key === chatPanel || key === characterPanel || infoWindows.holds(key)
    }

    /// Puts the character on screen. Safe when she is already showing.
    func showCharacter() {
        isCharacterVisible = true
        characterPanel.orderFrontRegardless()
    }

    /// Takes the character off the desktop, along with her chat. Safe when she
    /// is already hidden, which is what makes it usable from ⌘H — a toggle
    /// applied to everyone brings back whoever was already away.
    func hideCharacter() {
        isCharacterVisible = false
        if isChatVisible { hideChatPanel() }
        characterPanel.orderOut(nil)
    }

    /// Everything of hers, off the screen: her pinned panes as well as the
    /// bubble and the character. What ⌘H means by "the whole app".
    func hideEverythingOfHers() {
        infoWindows.hideAll()
        hideCharacter()
    }

    /// Shows or hides the floating character. Returns the new visibility so the
    /// menu can relabel its item. Hiding the character also hides the chat.
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

    /// Opens the chat, making the character visible first if it was hidden so the
    /// bubble has something to anchor to.
    func openChat() {
        showCharacter()
        showChatPanel()
    }

    func showChatPanel() {
        isChatVisible = true
        onDismissableChanged?()
        // Opening her chat is the clearest statement of which character the
        // person is working with, and the app-wide windows have to borrow one
        // character's look from somewhere.
        onUsed?()
        // The display may have changed since launch; re-clamp before showing,
        // against the screen the character is on rather than whichever one
        // happens to be "main" at the time.
        appearance.applyScreenLimits(
            (characterPanel.screen ?? NSScreen.main)?.visibleFrame
        )
        NSApp.activate(ignoringOtherApps: true)
        chatPanel.makeKeyAndOrderFront(nil)
        chatPanel.animator().alphaValue = 1
        // Clicking the character is someone starting to say something. Landing
        // in the box means they can just type; without it the bubble opened with
        // the caret nowhere and the first keystroke went into the void.
        chatLayout.requestInputFocus()
    }

    func hideChatPanel() {
        isChatVisible = false
        // Esc closes the chat; Esc again puts her away. Only the local monitor
        // can carry that second press, and it needs one of our windows to hold
        // the keyboard — closing the chat dropped it entirely, so the second
        // press reached nothing. Driven in the running app: two presses, chat
        // gone, character still there.
        //
        // This hands over a keyboard we already had; it never takes one. That
        // is why the character panel still refuses key status on a click, where
        // taking it would mean taking it from the app behind.
        if isCharacterVisible, chatPanel.isKeyWindow { characterPanel.makeKey() }
        // Esc goes back to whichever app the user is actually in the moment
        // there is nothing left to put away.
        onDismissableChanged?()
        chatPanel.animator().alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.chatPanel.orderOut(nil)
        }
    }

    /// Esc: a pinned pane in front is what it puts away; otherwise the chat.
    func dismissFrontmost() {
        if infoWindows.hideKeyWindow() { return }
        hideChatPanel()
    }
}
