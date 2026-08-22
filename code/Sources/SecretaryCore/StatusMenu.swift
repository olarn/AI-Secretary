import Foundation

public struct PinnedMenuRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

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

public enum StatusMenuAction: Equatable, Sendable {
    case toggleCharacter(character: UUID)
    case toggleAllCharacters
    case newChat(character: UUID)
    case resumeConversation(character: UUID, conversation: UUID)
    case clearHistory(character: UUID)
    case showPinned(character: UUID, window: UUID)
    case showAllPinned(character: UUID)
    case clearPinned(character: UUID)
    case newCharacter
    case toggleCommandWindow
    case showTokenUsage
    case showAbout
    case quit
}

public enum StatusMenuShortcut: String, Equatable, Sendable {
    case commandH = "h"
    case commandU = "u"
    case commandQ = "q"
}

public struct StatusMenuItem: Equatable, Sendable {
    public let title: String
    public let action: StatusMenuAction?
    public let shortcut: StatusMenuShortcut?
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

public func statusBarMenu(
    summary: String,
    characters: [CharacterMenuState],
    isCommandWindowVisible: Bool = false
) -> [StatusMenuEntry] {
    [
        .item(StatusMenuItem(title: summary, isEnabled: false)),
        .separator,
    ]
    + charactersSubmenu(characters)
    + [
        .separator,
        .item(StatusMenuItem(
            title: commandWindowMenuTitle(isVisible: isCommandWindowVisible),
            action: .toggleCommandWindow
        )),
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
            action: .toggleCharacter(character: character.id),
            submenu: characterSubmenu(character)
        ))
    }
    + (characters.isEmpty ? [] : [
        .separator,
        .item(StatusMenuItem(
            title: allCharactersTitle(characters),
            action: .toggleAllCharacters,
            shortcut: .commandH
        )),
    ])
    + [
        .item(StatusMenuItem(title: "New Character…", action: .newCharacter)),
    ]
}

public func allCharactersTitle(_ characters: [CharacterMenuState]) -> String {
    characters.contains(where: \.isVisible) ? "Hide All" : "Show All"
}

private func characterSubmenu(_ character: CharacterMenuState) -> [StatusMenuEntry] {
    [
        .item(StatusMenuItem(
            title: character.isVisible ? "Hide Character" : "Show Character",
            action: .toggleCharacter(character: character.id)
        )),
        .item(StatusMenuItem(title: "New chat", action: .newChat(character: character.id))),
        .item(StatusMenuItem(
            title: "Chat History",
            isEnabled: !character.history.isEmpty,
            submenu: historySubmenu(character)
        )),
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
        .separator,
        .item(StatusMenuItem(title: "Show All", action: .showAllPinned(character: character.id))),
        .item(StatusMenuItem(title: "Clear All", action: .clearPinned(character: character.id))),
    ]
}
