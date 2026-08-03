/// Whether ⌘H belongs to this app right now.
///
/// The chat bubble is a non-activating panel: it takes the keyboard without
/// making the app frontmost, so the menu bar still belongs to whatever the user
/// was in before. A menu key equivalent is searched in the *active* app's main
/// menu, which is why typing in the bubble and pressing ⌘H hid Safari, or the
/// terminal, or whatever happened to be behind — the keystroke was never ours
/// to begin with.
///
/// So it is claimed here instead, from the app's own event stream, and only
/// while one of this app's windows holds the keyboard. That keeps the promise
/// the owner set when a system-wide claim broke Hide everywhere: ⌘H stays an
/// ordinary per-app shortcut. The difference is that "this app" now means "the
/// window you are typing in" rather than "the app macOS thinks is in front",
/// which for a panel like this one are not the same thing.
///
/// - Parameters:
///   - isOurWindowKey: whether the keyboard currently belongs to one of this
///     app's windows. False means the user is typing somewhere else and their
///     ⌘H is none of our business.
///   - key: the character the key produces ignoring modifiers.
///   - hasOnlyCommand: Command held, and nothing else. ⌘⇧H is Hide Others and
///     ⌥⌘H is a different thing again; neither is ours to take.
public func handlesHideLocally(isOurWindowKey: Bool, key: String, hasOnlyCommand: Bool) -> Bool {
    isOurWindowKey && hasOnlyCommand && key.lowercased() == "h"
}
