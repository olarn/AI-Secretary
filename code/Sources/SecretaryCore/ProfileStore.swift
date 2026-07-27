import Foundation

/// The saved profile list plus which one is active.
public struct ProfileSelection: Equatable, Sendable, Codable {
    public var profiles: [SecretaryProfile]
    public var activeID: UUID?

    public init(profiles: [SecretaryProfile] = [], activeID: UUID? = nil) {
        self.profiles = profiles
        self.activeID = activeID
    }
}

/// Persistence boundary, so tests never touch the user's real Application
/// Support directory.
public protocol ProfileStoring: AnyObject, Sendable {
    func load() throws -> ProfileSelection
    func save(_ selection: ProfileSelection) throws
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

    public func load() throws -> ProfileSelection {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProfileSelection()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ProfileSelection.self, from: data)
    }

    public func save(_ selection: ProfileSelection) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(selection).write(to: fileURL, options: .atomic)
    }
}

public final class InMemoryProfileStore: ProfileStoring, @unchecked Sendable {
    private var selection: ProfileSelection

    public init(selection: ProfileSelection = ProfileSelection()) {
        self.selection = selection
    }

    public func load() throws -> ProfileSelection { selection }
    public func save(_ selection: ProfileSelection) throws { self.selection = selection }
}
