/// A key combination the app claims from the whole system, not just from its
/// own windows.
///
/// These are not ordinary shortcuts. A system-wide hot key *consumes* the
/// keystroke, so while one is claimed that combination stops meaning what it
/// used to mean in every other app. Which ones are claimed, and when, is
/// therefore a decision worth stating in one place and testing, rather than a
/// pair of register calls buried in window code.
/// ⌘H is deliberately **not** here. It was, briefly, and taking it broke Hide in
/// every other app on the machine — which is the whole hazard this type exists to
/// make visible. ⌘H stays an ordinary per-app shortcut, served by the menu item,
/// and works when this app is frontmost like everyone else's.
public enum GlobalShortcut: String, CaseIterable, Sendable {
    /// Esc — put the chat away, from anywhere.
    case closeChat

    /// Key code and modifier mask, in the form Carbon wants.
    public var keyCode: UInt32 {
        switch self {
        case .closeChat: 53   // kVK_Escape
        }
    }

    public var modifiers: UInt32 {
        switch self {
        case .closeChat: 0
        }
    }
}

/// Which shortcuts should be claimed right now.
///
/// `closeChat` is claimed only while the chat is on screen. Esc is the busiest
/// key on the keyboard — it cancels dialogs, leaves full screen, ends a Keynote
/// slideshow — and claiming it permanently would break all of that for the sake
/// of a window that isn't even showing. With the chat closed the shortcut has
/// nothing to do anyway, so releasing it costs nothing and hands Esc back to
/// whatever app the user is actually in.
///
/// Nothing at all is claimed while the chat is closed. A desktop companion that
/// is only sitting there has no business holding a key hostage.
public func claimedShortcuts(chatVisible: Bool) -> Set<GlobalShortcut> {
    chatVisible ? [.closeChat] : []
}
