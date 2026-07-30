import Foundation

/// Who the Up and Down keys belong to at this moment in the chat panel.
///
/// Three features want the same two keys: walking a question's options,
/// recalling what you sent earlier, and moving the caret inside a multi-line
/// draft. Leaving that to whichever handler runs first is how the arrows came
/// to feel broken — so ownership is decided here, as one total function over
/// the state, rather than by the order of `if`s inside an event monitor.
///
/// The deciding question is whether the message box is empty. An empty box
/// means you are answering the question that is on screen; the moment you type
/// something you are writing your own reply instead, and the picker steps
/// aside. That is the same rule Return already followed, now stated once for
/// both keys.
public enum ArrowKeyOwner: Equatable, Sendable {
    /// Move the highlight through the options; Return takes the highlighted one.
    case choiceList
    /// Step back and forth through messages already sent, as a terminal does.
    case history
    /// Leave the key alone so the text field moves the caret with it.
    case textCaret

    public static func owner(hasChoices: Bool, draft: String, hasHistory: Bool) -> ArrowKeyOwner {
        // A question on screen with nothing typed: the arrows are the picker's,
        // whether or not the caret happens to be in the box — the same reach as
        // Escape, because a picker you can see should answer to the keys you
        // press at it.
        if hasChoices, draft.isEmpty { return .choiceList }
        // In a draft that has more than one line the arrows are how you get
        // between them, so recall must not take them.
        if draft.contains("\n") { return .textCaret }
        return hasHistory ? .history : .textCaret
    }
}
