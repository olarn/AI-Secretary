import FunctionalCore
import Foundation
import Permissions
import ProjectRegistry

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

public protocol StandingGrantStoring: AnyObject, Sendable {
    func load() -> Either<GrantStoreError, [StandingGrant]>
    func save(_ grants: [StandingGrant]) -> Either<GrantStoreError, Void>
}

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
        let current = attempt { try JSONDecoder().decode([StandingGrantDTO].self, from: data) }
            .mapLeft { GrantStoreError.decodeFailed(path: fileURL.path, message: $0.localizedDescription) }^
            .map { $0.map(StandingGrant.init) }^
        return current.fold({ _ in self.adoptTheIdKeyedFile(data) }, { .right($0) })
    }

    private func adoptTheIdKeyedFile(_ data: Data) -> Either<GrantStoreError, [StandingGrant]> {
        attempt { try JSONDecoder().decode([IdKeyedGrantDTO].self, from: data) }
            .mapLeft { GrantStoreError.decodeFailed(path: fileURL.path, message: $0.localizedDescription) }^
            .map { old in
                let paths = self.projectPaths()
                let survivors = old.compactMap { paths[$0.projectID] }
                return Array(Set(survivors.map { StandingGrant(projectPath: $0) })).sorted()
            }^
            .map { migrated in
                _ = self.save(migrated)
                return migrated
            }^
    }

    private func projectPaths() -> [UUID: CanonicalPath] {
        let projects = fileURL.deletingLastPathComponent()
            .appendingPathComponent(
                fileURL.lastPathComponent
                    .replacingOccurrences(of: "permissions-", with: "projects-")
            )
        guard let data = try? Data(contentsOf: projects),
              let decoded = try? JSONDecoder().decode([ProjectPathDTO].self, from: data)
        else { return [:] }
        return Dictionary(
            decoded.map { ($0.id, CanonicalPath($0.path)) },
            uniquingKeysWith: { first, _ in first }
        )
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

struct StandingGrantDTO: Codable, Equatable, Sendable {
    var projectPath: CanonicalPath
}

struct IdKeyedGrantDTO: Codable, Equatable, Sendable {
    var projectID: UUID
    var toolID: String
    var actionClass: ActionClass
}

struct ProjectPathDTO: Codable, Equatable, Sendable {
    var id: UUID
    var path: String
}

extension StandingGrant {
    init(_ dto: StandingGrantDTO) {
        self.init(projectPath: dto.projectPath)
    }

    var dto: StandingGrantDTO {
        StandingGrantDTO(projectPath: projectPath)
    }
}
