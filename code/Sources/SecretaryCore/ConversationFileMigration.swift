import Foundation

/// What to do with the history file written before characters had their own.
///
/// The decision is here and the move is in the adapter, for the usual reason:
/// a migration that only runs on a machine that has the old file is a migration
/// nobody can test by running it, and getting it wrong costs the person every
/// conversation they have had.
public enum ConversationFileMigration: Equatable, Sendable {
    /// Nothing to do — either there is no old file, or this character already
    /// has one of her own and adopting would overwrite it.
    case none
    /// Rename the old file to be this character's.
    case adopt(from: URL, to: URL)
}

/// - Parameters:
///   - legacyExists: whether `conversations.json` is on disk.
///   - perCharacterExists: whether this character's own file already is. If it
///     is, she has been through this once and the old file is somebody else's
///     problem — never overwrite what she has now with what everyone shared
///     then.
public func conversationFileMigration(
    legacy: URL,
    perCharacter: URL,
    legacyExists: Bool,
    perCharacterExists: Bool
) -> ConversationFileMigration {
    guard legacyExists, !perCharacterExists else { return .none }
    return .adopt(from: legacy, to: perCharacter)
}
