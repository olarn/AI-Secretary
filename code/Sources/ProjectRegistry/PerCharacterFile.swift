import Foundation

/// What to do with a file that was written while there was one character, now
/// that each character keeps her own.
///
/// The decision is a value and the move is in the adapter, for the reason the
/// conversation history gave first: a migration that only runs on a machine
/// holding the old file is a migration nobody can test by running it, and
/// getting it wrong costs the person everything the file held.
public enum FileMigration: Equatable, Sendable {
    /// Nothing to do — either there is no old file, or this character already
    /// has one of her own and adopting would overwrite it.
    case none
    case adopt(from: URL, to: URL)
}

/// - Parameters:
///   - legacyExists: whether the shared file is on disk.
///   - perCharacterExists: whether this character's own file already is. If it
///     is, she has been through this once and the old file is somebody else's
///     problem — never overwrite what she has now with what everyone shared
///     then.
public func perCharacterFileMigration(
    legacy: URL,
    perCharacter: URL,
    legacyExists: Bool,
    perCharacterExists: Bool
) -> FileMigration {
    guard legacyExists, !perCharacterExists else { return .none }
    return .adopt(from: legacy, to: perCharacter)
}
