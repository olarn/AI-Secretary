import Foundation
import ProjectRegistry

public typealias ConversationFileMigration = FileMigration

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
