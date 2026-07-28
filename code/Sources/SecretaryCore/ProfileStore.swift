import FunctionalCore
import Foundation

/// The saved profile list plus which one is active.
///
/// Not `Codable` — `Option` cannot be. `ProfileSelectionDTO` is the on-disk
/// shape and keeps the same JSON keys, so existing `profiles.json` files load
/// unchanged.
public struct ProfileSelection: Equatable, Sendable {
    public var profiles: [SecretaryProfile]
    public var activeID: Option<UUID>

    public init(profiles: [SecretaryProfile] = [], activeID: Option<UUID> = .none()) {
        self.profiles = profiles
        self.activeID = activeID
    }
}

// MARK: - Persistence edge

public struct ProfileSelectionDTO: Codable, Equatable, Sendable {
    public var profiles: [SecretaryProfile]
    public var activeID: UUID?
}

extension ProfileSelection {
    public init(_ dto: ProfileSelectionDTO) {
        self.init(profiles: dto.profiles, activeID: Option.fromOptional(dto.activeID))
    }

    public var dto: ProfileSelectionDTO {
        ProfileSelectionDTO(profiles: profiles, activeID: activeID.toOptional())
    }
}

/// Why the profile list could not be read or written.
public enum ProfileStoreError: Error, Equatable, Sendable {
    case readFailed(path: String, message: String)
    case decodeFailed(path: String, message: String)
    case writeFailed(path: String, message: String)

    public var reason: String {
        switch self {
        case let .readFailed(path, message):
            return "Couldn't read profiles at \(path): \(message)"
        case let .decodeFailed(path, message):
            return "The profile file at \(path) is not readable: \(message)"
        case let .writeFailed(path, message):
            return "Couldn't save profiles to \(path): \(message)"
        }
    }
}

/// Persistence boundary, so tests never touch the user's real Application
/// Support directory.
public protocol ProfileStoring: AnyObject, Sendable {
    func load() -> Either<ProfileStoreError, ProfileSelection>
    func save(_ selection: ProfileSelection) -> Either<ProfileStoreError, Void>
}

/// Stores profiles as JSON beside the project registry. Pictures are not in
/// here — they live as files under `ProfileArtwork`, keyed by profile id.
public final class FileProfileStore: ProfileStoring, @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileProfileStore.defaultURL
    }

    public static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    public func load() -> Either<ProfileStoreError, ProfileSelection> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .right(ProfileSelection())
        }

        return attempt { try Data(contentsOf: fileURL) }
            .mapLeft { ProfileStoreError.readFailed(path: fileURL.path, message: $0.localizedDescription) }^
            .flatMap(decode)^
    }

    private func decode(_ data: Data) -> Either<ProfileStoreError, ProfileSelection> {
        attempt { try JSONDecoder().decode(ProfileSelectionDTO.self, from: data) }
            .mapLeft { ProfileStoreError.decodeFailed(path: fileURL.path, message: $0.localizedDescription) }^
            .map(ProfileSelection.init)^
    }

    public func save(_ selection: ProfileSelection) -> Either<ProfileStoreError, Void> {
        attempt {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(selection.dto).write(to: fileURL, options: .atomic)
        }
        .mapLeft { .writeFailed(path: fileURL.path, message: $0.localizedDescription) }^
    }
}

public final class InMemoryProfileStore: ProfileStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var selection: ProfileSelection

    public init(selection: ProfileSelection = ProfileSelection()) {
        self.selection = selection
    }

    public func load() -> Either<ProfileStoreError, ProfileSelection> {
        lock.lock(); defer { lock.unlock() }
        return .right(selection)
    }

    public func save(_ selection: ProfileSelection) -> Either<ProfileStoreError, Void> {
        lock.lock(); defer { lock.unlock() }
        self.selection = selection
        return .right(())
    }
}
