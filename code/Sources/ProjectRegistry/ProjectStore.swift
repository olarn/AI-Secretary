import FunctionalCore
import Foundation

/// Why reading or writing the registry failed. Per-module, so nothing outside
/// `ProjectRegistry` has to know about `Codable` or file paths.
public enum ProjectStoreError: Error, Equatable, Sendable {
    case readFailed(path: String, message: String)
    case decodeFailed(path: String, message: String)
    case writeFailed(path: String, message: String)
}

extension ProjectStoreError {
    public var reason: String {
        switch self {
        case let .readFailed(path, message):
            return "Couldn't read the project list at \(path): \(message)"
        case let .decodeFailed(path, message):
            return "The project list at \(path) is not readable: \(message)"
        case let .writeFailed(path, message):
            return "Couldn't save the project list to \(path): \(message)"
        }
    }
}

/// Persistence boundary for the registry, so tests can swap in an in-memory
/// store instead of touching the user's real Application Support directory.
///
/// Failures come back as values rather than thrown errors: loading a registry
/// at launch must not be able to unwind through an initialiser.
public protocol ProjectStoring: AnyObject, Sendable {
    func load() -> Either<ProjectStoreError, [Project]>
    func save(_ projects: [Project]) -> Either<ProjectStoreError, Void>
}

/// Stores the registry as JSON under Application Support. Kept separate from
/// chat history so project paths and permissions never mix with conversation
/// content.
///
/// This is the Foundation edge: `FileManager` and `JSONDecoder` keep throwing,
/// and every throw is converted to the left rail exactly once, here.
public final class FileProjectStore: ProjectStoring, @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileProjectStore.defaultURL
    }

    /// Where the registry lived while every character shared one. Still read
    /// once, to be adopted — see `adoptLegacyProjects`.
    public static var defaultURL: URL {
        supportDirectory.appendingPathComponent("projects.json")
    }

    /// One file per character.
    ///
    /// A project row is not a bookmark: it carries `allowedTools`, so the file
    /// is the character's allowlist. Sharing it means approving Claude Code for
    /// one character approves it for all of them, which is the thing this
    /// separation is for.
    public static func url(forCharacter id: UUID) -> URL {
        supportDirectory.appendingPathComponent("projects-\(id.uuidString).json")
    }

    private static var supportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
    }

    /// Hands the shared registry to a character, once.
    ///
    /// The decision is `perCharacterFileMigration`; this reads the two `exists`
    /// answers off the disk and applies what it says. Returns what it decided
    /// so a caller can see whether anything moved.
    @discardableResult
    public static func adoptLegacyProjects(
        for id: UUID,
        fileManager: FileManager = .default
    ) -> Either<ProjectStoreError, FileMigration> {
        let legacy = defaultURL
        let mine = url(forCharacter: id)
        let decision = perCharacterFileMigration(
            legacy: legacy,
            perCharacter: mine,
            legacyExists: fileManager.fileExists(atPath: legacy.path),
            perCharacterExists: fileManager.fileExists(atPath: mine.path)
        )
        guard case .adopt(let from, let to) = decision else { return .right(decision) }
        return attempt {
            try fileManager.createDirectory(
                at: to.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: from, to: to)
        }
        .mapLeft { ProjectStoreError.writeFailed(path: to.path, message: $0.localizedDescription) }^
        .map { decision }^
    }

    public func load() -> Either<ProjectStoreError, [Project]> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .right([]) }

        return readData()
            .flatMap(decodeProjects)^
    }

    private func readData() -> Either<ProjectStoreError, Data> {
        attempt { try Data(contentsOf: fileURL) }
            .mapLeft { .readFailed(path: fileURL.path, message: $0.localizedDescription) }^
    }

    private func decodeProjects(_ data: Data) -> Either<ProjectStoreError, [Project]> {
        attempt { try JSONDecoder().decode([ProjectDTO].self, from: data) }
            .mapLeft { ProjectStoreError.decodeFailed(path: fileURL.path, message: $0.localizedDescription) }^
            .map { $0.map(Project.init) }^
    }

    public func save(_ projects: [Project]) -> Either<ProjectStoreError, Void> {
        attempt {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(projects.map(\.dto)).write(to: fileURL, options: .atomic)
        }
        .mapLeft { .writeFailed(path: fileURL.path, message: $0.localizedDescription) }^
    }
}

/// In-memory store for tests.
public final class InMemoryProjectStore: ProjectStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var projects: [Project]

    public init(projects: [Project] = []) {
        self.projects = projects
    }

    public func load() -> Either<ProjectStoreError, [Project]> {
        lock.lock(); defer { lock.unlock() }
        return .right(projects)
    }

    public func save(_ projects: [Project]) -> Either<ProjectStoreError, Void> {
        lock.lock(); defer { lock.unlock() }
        self.projects = projects
        return .right(())
    }
}
