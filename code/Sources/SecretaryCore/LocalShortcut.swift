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
/// **Matched on the key's position, never on the character it produces.** This
/// took `key: String` and compared it to `"h"`, which is only the letter H on a
/// Latin layout. The owner types Thai: with Kedmanee active the same key reports
/// `charactersIgnoringModifiers` as `้` (U+0E49), the comparison failed, the
/// monitor handed the event on, and the stale `Hide Character` item in the main
/// menu answered it instead — so ⌘H hid one character rather than the whole app,
/// exactly the behaviour Sprint 13-2 replaced. It looked like the feature had
/// been reverted; nothing had changed but the input source.
///
/// Measured on 2026-08-17 by logging the event: `code=4`,
/// `chars=Optional("\u{0E49}")`, `flags=1048576`, `keyWindow=true`. The control
/// in the same log is ⌘V, which kept working — main-menu key equivalents are
/// matched layout-independently by AppKit, and only this hand-rolled comparison
/// was not.
///
/// The test that should have caught it was called
/// `testCapitalsAndLayoutsAreTheSameKey` and checked `"h"` against `"H"`, which
/// is a *capital*, not another layout. Anything comparing a typed character to a
/// Latin letter has this bug; `keyCode` is the same number on every layout.
///
/// - Parameters:
///   - isOurWindowKey: whether the keyboard currently belongs to one of this
///     app's windows. False means the user is typing somewhere else and their
///     ⌘H is none of our business.
///   - keyCode: the hardware key, which does not move when the layout changes.
///   - hasOnlyCommand: Command held, and nothing else. ⌘⇧H is Hide Others and
///     ⌥⌘H is a different thing again; neither is ours to take.
public func handlesHideLocally(
    isOurWindowKey: Bool,
    keyCode: UInt16,
    hasOnlyCommand: Bool
) -> Bool {
    isOurWindowKey && hasOnlyCommand && keyCode == 4   // kVK_ANSI_H
}
