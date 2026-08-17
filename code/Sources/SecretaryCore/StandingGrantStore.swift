import FunctionalCore
import Foundation
import Permissions

public enum GrantStoreError: Error, Equatable, Sendable {
    case readFailed(path: String, message: String)
    case decodeFailed(path: String, message: String)
    case writeFailed(path: String, message: String)

    public var reason: String {
        switch self {
        case let .readFailed(path, message):
            return "Couldn't read the remembered permissions at \(path): \(message)"
        case let .decodeFailed(path, message):
            return "The remembered permissions at \(path) are not readable: \(message)"
        case let .writeFailed(path, message):
            return "Couldn't save the remembered permission to \(path): \(message)"
        }
    }
}

/// Where the grants that outlive a conversation are kept.
///
/// Failures come back as values rather than thrown errors, for the same reason
/// the project registry's do: loading happens in an initialiser, and an
/// initialiser is no place to unwind from.
public protocol StandingGrantStoring: AnyObject, Sendable {
    func load() -> Either<GrantStoreError, [StandingGrant]>
    func save(_ grants: [StandingGrant]) -> Either<GrantStoreError, Void>
}

/// The app's own file, under Application Support, one per character.
///
/// **Deliberately not the project's Claude Code memory** (owner's decision,
/// 2026-08-17), which the backlog item could have been read as asking for.
/// That directory is loaded into the model's context on every turn and is read
/// by the person's own terminal `claude` — so a grant written there would be
/// instruction-shaped text the model can see, and a permission this app gave
/// itself would silently apply outside this app. Here it is the app's own
/// record: invisible to the model, and deletable by deleting the file.
///
/// Per character for the same reason the project registry is: a grant is one
/// character's answer about one of her projects, and sharing the file would
/// mean approving something for Miku approves it for everyone.
public final class FileStandingGrantStore: StandingGrantStoring, @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func url(forCharacter id: UUID) -> URL {
        supportDirectory.appendingPathComponent("permissions-\(id.uuidString).json")
    }

    private static var supportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
    }

    public func load() -> Either<GrantStoreError, [StandingGrant]> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .right([]) }
        return attempt { try Data(contentsOf: fileURL) }
            .mapLeft { GrantStoreError.readFailed(path: fileURL.path, message: $0.localizedDescription) }^
            .flatMap(decode)^
    }

    private func decode(_ data: Data) -> Either<GrantStoreError, [StandingGrant]> {
        attempt { try JSONDecoder().decode([StandingGrantDTO].self, from: data) }
            .mapLeft { GrantStoreError.decodeFailed(path: fileURL.path, message: $0.localizedDescription) }^
            .map { $0.map(StandingGrant.init) }^
    }

    public func save(_ grants: [StandingGrant]) -> Either<GrantStoreError, Void> {
        attempt {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(grants.map(\.dto)).write(to: fileURL, options: .atomic)
        }
        .mapLeft { .writeFailed(path: fileURL.path, message: $0.localizedDescription) }^
    }
}

/// Nowhere, for tests and for a character whose store hasn't been built yet.
public final class InMemoryStandingGrantStore: StandingGrantStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var grants: [StandingGrant]

    public init(grants: [StandingGrant] = []) {
        self.grants = grants
    }

    public func load() -> Either<GrantStoreError, [StandingGrant]> {
        lock.lock(); defer { lock.unlock() }
        return .right(grants)
    }

    public func save(_ grants: [StandingGrant]) -> Either<GrantStoreError, Void> {
        lock.lock(); defer { lock.unlock() }
        self.grants = grants
        return .right(())
    }
}

// MARK: - Persistence edge

struct StandingGrantDTO: Codable, Equatable, Sendable {
    var projectID: UUID
    var toolID: String
    var actionClass: ActionClass
}

extension StandingGrant {
    init(_ dto: StandingGrantDTO) {
        self.init(projectID: dto.projectID, toolID: dto.toolID, actionClass: dto.actionClass)
    }

    var dto: StandingGrantDTO {
        StandingGrantDTO(projectID: projectID, toolID: toolID, actionClass: actionClass)
    }
}
