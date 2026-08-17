import Foundation

/// One character, as far as Esc is concerned.
public struct DismissCandidate: Equatable, Sendable {
    public let id: UUID
    /// Whether one of her windows currently holds the keyboard.
    public let holdsKeyboard: Bool
    /// Whether she has anything Esc would put away — a chat bubble up, or a
    /// pinned pane.
    public let hasDismissable: Bool
    /// Whether she is on the desktop at all. The last rung of the ladder: with
    /// nothing left to put away, Esc puts *her* away.
    public let isCharacterVisible: Bool

    public init(
        id: UUID,
        holdsKeyboard: Bool,
        hasDismissable: Bool,
        isCharacterVisible: Bool = false
    ) {
        self.id = id
        self.holdsKeyboard = holdsKeyboard
        self.hasDismissable = hasDismissable
        self.isCharacterVisible = isCharacterVisible
    }
}

/// Whether Esc has anything to put away for one character.
///
/// **Counts panes that are on screen, never panes that merely exist.** The set
/// behind a character's pinned panes deliberately keeps every pane that was ever
/// pinned — the status-bar menu is built from it, and a pane that Esc put away
/// has to stay listed so one click brings it back. Asking that set whether it is
/// *empty* therefore answers a different question from the one Esc asks, and it
/// answers `true` for the rest of the session after the very first pin.
///
/// What that cost, driven on 2026-08-17 at v0.17.278: pin one box, press Esc to
/// put the pane away, press Esc again to close the chat — and the third press,
/// the one that should hide the character, did nothing, then or ever again in
/// that session. `dismissDecision` was right to refuse; it was being told
/// something was still on screen. The same wrong answer keeps the system-wide
/// Esc claim registered with nothing of ours visible, so the key is taken from
/// every other app and spent on doing nothing.
public func hasSomethingToDismiss(isChatVisible: Bool, visiblePanes: Int) -> Bool {
    isChatVisible || visiblePanes > 0
}

/// Where an Esc press came from.
///
/// The two paths are not interchangeable and the difference is the whole reason
/// this is a parameter rather than an assumption:
///
/// - `.hotKey` is the system-wide claim. It arrives from anywhere, including
///   while the person is typing in another app, so it may only put windows
///   away — never hide a character somebody isn't looking at.
/// - `.ownWindow` is the local monitor, which by construction only sees the key
///   when one of this app's windows holds the keyboard.
public enum DismissTrigger: Equatable, Sendable {
    case hotKey
    case ownWindow
}

/// What Esc does, and to whom.
public enum DismissStep: Equatable, Sendable {
    /// Put away the frontmost thing she has — a pinned pane, else the chat.
    case dismissWindow
    /// Take her off the desktop.
    case hideCharacter
}

public struct DismissDecision: Equatable, Sendable {
    public let id: UUID
    public let step: DismissStep

    public init(id: UUID, step: DismissStep) {
        self.id = id
        self.step = step
    }
}

/// What Esc means right now.
///
/// Esc is claimed from the whole system, once, because that is all the system
/// grants — so with several characters on the desktop something has to decide
/// whose window it means. It went to `characters.first` for a while, which is
/// how Esc stopped working: type in the third character's bubble, press Esc,
/// and the first character's chat is asked to close, which it usually is not
/// even showing. The key that had always put the chat away appeared to do
/// nothing.
///
/// The keyboard is the answer when there is one — you are typing in her, so she
/// is the one you mean. Failing that, anybody with something to put away, in
/// roster order, so Esc still works when the pointer never entered a bubble.
///
/// **Two Esc handlers exist, and this function is what keeps them from both
/// firing.** The hot key is registered only while something is dismissable
/// (`claimedShortcuts`), and while registered it consumes the keystroke before
/// any local monitor sees it. Rather than trust that ordering, the rule is
/// written down: a local press with anything dismissable on screen belongs to
/// the hot key and this returns `nil`, so the local monitor lets the event
/// through instead of acting on it. Exactly one of the two paths ever answers.
///
/// Hiding a character is deliberately unreachable from `.hotKey`. Esc is the
/// busiest key on the keyboard, and a companion that vanished because somebody
/// dismissed a dialog in Photoshop would be a bug, not a feature.
public func dismissDecision(
    _ candidates: [DismissCandidate],
    trigger: DismissTrigger = .hotKey
) -> DismissDecision? {
    let dismissable = candidates.filter(\.hasDismissable)

    if trigger == .ownWindow {
        guard dismissable.isEmpty else { return nil }
        return candidates
            .first { $0.holdsKeyboard && $0.isCharacterVisible }
            .map { DismissDecision(id: $0.id, step: .hideCharacter) }
    }

    let chosen = dismissable.first(where: \.holdsKeyboard) ?? dismissable.first
    return chosen.map { DismissDecision(id: $0.id, step: .dismissWindow) }
}
