import Foundation
import ProjectRegistry

/// What to do with the history file written before characters had their own.
///
/// This was the first per-character migration and the shape it found is now
/// shared with the project registry, which needed the same decision word for
/// word. The name stays because the history file's callers read better with
/// it, and because it is the name its tests know.
public typealias ConversationFileMigration = FileMigration

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
    perCharacterFileMigration(
        legacy: legacy,
        perCharacter: perCharacter,
        legacyExists: legacyExists,
        perCharacterExists: perCharacterExists
    )
}
