import Foundation

/// One character, as far as Esc is concerned.
public struct DismissCandidate: Equatable, Sendable {
    public let id: UUID
    /// Whether one of her windows currently holds the keyboard.
    public let holdsKeyboard: Bool
    /// Whether she has anything Esc would put away — a chat bubble up, or a
    /// pinned pane.
    public let hasDismissable: Bool

    public init(id: UUID, holdsKeyboard: Bool, hasDismissable: Bool) {
        self.id = id
        self.holdsKeyboard = holdsKeyboard
        self.hasDismissable = hasDismissable
    }
}

/// Which character Esc acts on.
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
public func dismissTarget(_ candidates: [DismissCandidate]) -> UUID? {
    if let typing = candidates.first(where: { $0.holdsKeyboard && $0.hasDismissable }) {
        return typing.id
    }
    return candidates.first(where: \.hasDismissable)?.id
}
