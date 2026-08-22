import Foundation

public enum FileMigration: Equatable, Sendable {
    case none
    case adopt(from: URL, to: URL)
}

public func perCharacterFileMigration(
    legacy: URL,
    perCharacter: URL,
    legacyExists: Bool,
    perCharacterExists: Bool
) -> FileMigration {
    let adoptingWouldOverwriteWhatSheAlreadyHas = perCharacterExists
    guard legacyExists, !adoptingWouldOverwriteWhatSheAlreadyHas else { return .none }
    return .adopt(from: legacy, to: perCharacter)
}
