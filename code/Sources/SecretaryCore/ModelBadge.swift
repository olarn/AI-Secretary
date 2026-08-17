import Foundation

/// One spelling for "the app was not told, so whatever Claude Code picks will
/// run". Said in the settings panel, in the chat header, and to the other
/// characters in `directoryPrompt`; three spellings would read as three
/// different situations.
public let inheritedSettingName = "Default"

/// The model's name with the maker's dropped — "Claude Opus 5" → "Opus 5".
///
/// Every model this app can reach is a Claude, so the word carries no
/// information and costs six characters in a header row that already holds a
/// name, a state tag and up to five badges. `CharacterCard.model` has always
/// documented itself as holding this shorter form; until now the app handed it
/// a raw model id instead.
public func shortModelName(_ displayName: String) -> String {
    let prefix = "Claude "
    guard displayName.hasPrefix(prefix) else { return displayName }
    return String(displayName.dropFirst(prefix.count))
}

/// What the character is running, for the header beside her name.
///
/// Both halves collapse to one word when neither is known, because
/// "Default | Default" says the same thing twice and reads as two settings
/// that happen to match rather than as one absence. The separator is the pipe
/// the owner asked for.
public func modelBadge(model: String, effort: String) -> String {
    let short = shortModelName(model)
    guard short != inheritedSettingName || effort != inheritedSettingName else {
        return inheritedSettingName
    }
    return "\(short) | \(effort)"
}
