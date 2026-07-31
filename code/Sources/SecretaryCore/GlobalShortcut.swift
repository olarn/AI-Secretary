/// A key combination the app claims from the whole system, not just from its
/// own windows.
///
/// These are not ordinary shortcuts. A system-wide hot key *consumes* the
/// keystroke, so while one is claimed that combination stops meaning what it
/// used to mean in every other app. Which ones are claimed, and when, is
/// therefore a decision worth stating in one place and testing, rather than a
/// pair of register calls buried in window code.
public enum GlobalShortcut: String, CaseIterable, Sendable {
    /// ⌘H — hide the character and the chat together, from anywhere.
    case hideApp
    /// Esc — put the chat away, from anywhere.
    case closeChat

    /// Key code and modifier mask, in the form Carbon wants.
    public var keyCode: UInt32 {
        switch self {
        case .hideApp: 4      // kVK_ANSI_H
        case .closeChat: 53   // kVK_Escape
        }
    }

    /// `cmdKey` is Carbon's 0x0100. Spelled out rather than imported so this
    /// stays a plain value type that tests can reach without AppKit.
    public var modifiers: UInt32 {
        switch self {
        case .hideApp: 0x0100
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
/// `hideApp` is claimed always, which is the cost of "⌘H works from anywhere":
/// other apps stop hiding on ⌘H while this one runs. It toggles, so the same
/// key brings the character back — otherwise hiding from another app would
/// leave no way in except the status bar.
public func claimedShortcuts(chatVisible: Bool) -> Set<GlobalShortcut> {
    chatVisible ? [.hideApp, .closeChat] : [.hideApp]
}
