import Foundation

/// The status bar menu, as a value.
///
/// `AISecretaryApp` is never linked into the test bundle, so a menu built by
/// hand out of `NSMenuItem`s is a hundred-odd lines that no test has ever
/// executed — and Phase 13 turns those hundred lines into a tree three levels
/// deep with a branch per character. The rule the charter draws for exactly
/// this case is that the app applies answers rather than computing them, so
/// the shape lives here, where it can be asserted row by row, and
/// `StatusBarController` becomes a renderer.
///
/// Plain Swift, no Bow: this crosses into the app target, which cannot import
/// `FunctionalCore` without Bow's `State` shadowing SwiftUI's — the same reason
/// `ConversationMenuRow` next door is plain.

// MARK: - What the menu is built from

/// One pinned pane, reduced to what a menu row needs. `InfoWindowSpec` carries
/// its body and timestamp too, and a menu that receives those invites itself to
/// start deciding things about them.
public struct PinnedMenuRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

/// Everything the menu needs to know about one character.
public struct CharacterMenuState: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let isVisible: Bool
    public let history: [ConversationMenuRow]
    public let pinned: [PinnedMenuRow]

    public init(
        id: UUID,
        name: String,
        isVisible: Bool,
        history: [ConversationMenuRow] = [],
        pinned: [PinnedMenuRow] = []
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.history = history
        self.pinned = pinned
    }
}

// MARK: - What the menu is

/// What a row does when it is clicked. A closed set, so the renderer cannot
/// invent an action and the tests can name every one that exists.
public enum StatusMenuAction: Equatable, Sendable {
    case toggleCharacter(character: UUID)
    case newChat(character: UUID)
    case resumeConversation(character: UUID, conversation: UUID)
    case clearHistory(character: UUID)
    case showPinned(character: UUID, window: UUID)
    case showAllPinned(character: UUID)
    case clearPinned(character: UUID)
    case newCharacter
    case showTokenUsage
    case showAbout
    case quit
}

/// A keystroke the row advertises. Command-only, because every shortcut this
/// menu has ever carried is.
public enum StatusMenuShortcut: String, Equatable, Sendable {
    case commandH = "h"
    case commandU = "u"
    case commandQ = "q"
}

public struct StatusMenuItem: Equatable, Sendable {
    public let title: String
    /// Absent for a label or a submenu parent — rows that are not clicked.
    public let action: StatusMenuAction?
    public let shortcut: StatusMenuShortcut?
    /// Drawn with a tick. Marks the conversation you are already in; without it
    /// reopening it is an invisible no-op that reads as the menu being broken.
    public let isChecked: Bool
    public let isEnabled: Bool
    public let submenu: [StatusMenuEntry]?

    public init(
        title: String,
        action: StatusMenuAction? = nil,
        shortcut: StatusMenuShortcut? = nil,
        isChecked: Bool = false,
        isEnabled: Bool = true,
        submenu: [StatusMenuEntry]? = nil
    ) {
        self.title = title
        self.action = action
        self.shortcut = shortcut
        self.isChecked = isChecked
        self.isEnabled = isEnabled
        self.submenu = submenu
    }
}

public enum StatusMenuEntry: Equatable, Sendable {
    case separator
    case item(StatusMenuItem)
}

// MARK: - The menu

/// The whole tree, from `menu.pdf`.
///
/// ```text
/// AI Secretary 0.13.x
/// ├ Miku ▸ ──────── Show/Hide Character
/// ├ Anya ▸          New chat
/// ├ New Character…  Chat History ▸
/// ├ Token Usage     ─────────
/// ├ About           Pinned Messages ▸
/// └ Quit
/// ```
///
/// Everything about a conversation hangs off the character it belongs to; only
/// the three rows that are about the app stay at the root.
///
/// The characters used to sit one level further in, under a "Characters" row.
/// That row held nothing of its own — it existed to be hovered past — so the
/// owner asked for it gone and the characters moved up into its place.
public func statusBarMenu(summary: String, characters: [CharacterMenuState]) -> [StatusMenuEntry] {
    [
        // A label, not a row to click: it answers "which version am I running"
        // without opening anything.
        .item(StatusMenuItem(title: summary, isEnabled: false)),
        .separator,
    ]
    + charactersSubmenu(characters)
    + [
        .separator,
        .item(StatusMenuItem(title: "Token Usage", action: .showTokenUsage, shortcut: .commandU)),
        .item(StatusMenuItem(title: "About \(AppInfo.name)", action: .showAbout)),
        .separator,
        .item(StatusMenuItem(title: "Quit \(AppInfo.name)", action: .quit, shortcut: .commandQ)),
    ]
}

private func charactersSubmenu(_ characters: [CharacterMenuState]) -> [StatusMenuEntry] {
    characters.map { character in
        .item(StatusMenuItem(
            title: character.name,
            // Clicking her name shows or hides her, which is the thing anyone
            // wants from a character row often enough to be worth a click
            // rather than a hover and a second click. Her submenu is still
            // there for everything else.
            action: .toggleCharacter(character: character.id),
            submenu: characterSubmenu(character)
        ))
    }
    + [
        // Always after them, so its position doesn't move as characters come
        // and go.
        .item(StatusMenuItem(title: "New Character…", action: .newCharacter)),
    ]
}

private func characterSubmenu(_ character: CharacterMenuState) -> [StatusMenuEntry] {
    [
        // ⌘H is advertised on every character but only ever reaches the
        // focused one — the system grants the keystroke once. The row is still
        // where someone finds out the shortcut exists.
        .item(StatusMenuItem(
            title: character.isVisible ? "Hide Character" : "Show Character",
            action: .toggleCharacter(character: character.id),
            shortcut: .commandH
        )),
        .item(StatusMenuItem(title: "New chat", action: .newChat(character: character.id))),
        .item(StatusMenuItem(
            title: "Chat History",
            isEnabled: !character.history.isEmpty,
            submenu: historySubmenu(character)
        )),
        // Everything above is the conversation; below is what was pulled out
        // of one. The line is where that changes.
        .separator,
        .item(StatusMenuItem(
            title: "Pinned Messages",
            isEnabled: !character.pinned.isEmpty,
            submenu: pinnedSubmenu(character)
        )),
    ]
}

private func historySubmenu(_ character: CharacterMenuState) -> [StatusMenuEntry] {
    guard !character.history.isEmpty else {
        return [.item(StatusMenuItem(title: "No past conversations", isEnabled: false))]
    }
    return character.history.map { row in
        .item(StatusMenuItem(
            title: row.label,
            action: .resumeConversation(character: character.id, conversation: row.id),
            isChecked: row.isCurrent
        ))
    } + [
        .separator,
        .item(StatusMenuItem(title: "Clear All", action: .clearHistory(character: character.id))),
    ]
}

/// Clicking a pane brings it forward. Deleting one lives on its own close
/// button and on Clear All: a row whose whole job is "show me this" should not
/// need a submenu in front of it, and a Delete one pixel from Show is a
/// mis-click waiting to throw away the thing you meant to look at.
private func pinnedSubmenu(_ character: CharacterMenuState) -> [StatusMenuEntry] {
    guard !character.pinned.isEmpty else {
        return [.item(StatusMenuItem(title: "Nothing pinned yet", isEnabled: false))]
    }
    return character.pinned.map { row in
        .item(StatusMenuItem(
            title: row.title,
            action: .showPinned(character: character.id, window: row.id)
        ))
    } + [
        // Always last, in this order, so their positions don't move as panes
        // come and go.
        .separator,
        .item(StatusMenuItem(title: "Show All", action: .showAllPinned(character: character.id))),
        .item(StatusMenuItem(title: "Clear All", action: .clearPinned(character: character.id))),
    ]
}
