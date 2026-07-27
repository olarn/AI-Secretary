import Foundation

/// Persistence boundary for the registry, so tests can swap in an in-memory
/// store instead of touching the user's real Application Support directory.
public protocol ProjectStoring: AnyObject, Sendable {
    func load() throws -> [Project]
    func save(_ projects: [Project]) throws
}

/// Stores the registry as JSON under Application Support. Kept separate from
/// chat history so project paths and permissions never mix with conversation
/// content.
public final class FileProjectStore: ProjectStoring, @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileProjectStore.defaultURL
    }

    public static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
            .appendingPathComponent("projects.json")
    }

    public func load() throws -> [Project] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([Project].self, from: data)
    }

    public func save(_ projects: [Project]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(projects).write(to: fileURL, options: .atomic)
    }
}

/// In-memory store for tests.
public final class InMemoryProjectStore: ProjectStoring, @unchecked Sendable {
    private var projects: [Project]

    public init(projects: [Project] = []) {
        self.projects = projects
    }

    public func load() throws -> [Project] { projects }
    public func save(_ projects: [Project]) throws { self.projects = projects }
}
