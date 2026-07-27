import Foundation
import Observation

/// The single source of truth for which directories the assistant may work in.
@Observable
public final class ProjectRegistry {
    public private(set) var projects: [Project] = []

    @ObservationIgnored private let store: ProjectStoring

    public init(store: ProjectStoring = FileProjectStore()) {
        self.store = store
        projects = (try? store.load()) ?? []
    }

    /// Whether a project already points at the same directory. Paths are
    /// compared after standardising, so "/a/b" and "/a/b/" are one place.
    public func containsProject(atPath path: String) -> Bool {
        let target = Self.normalize(path)
        return projects.contains { Self.normalize($0.path) == target }
    }

    /// Registers a project unless its directory is already registered, in
    /// which case the existing entry is kept and this returns `false`. This is
    /// what keeps "Add project…" from creating duplicate rows for one folder.
    @discardableResult
    public func add(_ project: Project) throws -> Bool {
        guard !containsProject(atPath: project.path) else { return false }
        projects.append(project)
        try store.save(projects)
        return true
    }

    /// Adds a tool to a project's allowlist and persists it.
    ///
    /// Called at the moment a human approves the capability, never on load — a
    /// project registered before a tool existed must not silently gain it.
    @discardableResult
    public func grant(tool: String, to projectID: UUID) throws -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }),
              !projects[index].allowedTools.contains(tool)
        else { return false }
        projects[index].allowedTools.append(tool)
        try store.save(projects)
        return true
    }

    private static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public func remove(id: UUID) throws {
        projects.removeAll { $0.id == id }
        try store.save(projects)
    }

    public func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    /// Resolves a project reference from user text. Matching is by name only —
    /// a filesystem path is never derived from the query, so an unregistered
    /// name resolves to `.notFound` rather than a guessed directory.
    public func resolve(query: String?) -> ProjectResolution {
        guard let query, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            if projects.count == 1, let only = projects.first {
                return .resolved(only)
            }
            return .needsSelection(candidates: projects)
        }

        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()

        let exact = projects.filter { $0.name.lowercased() == needle }
        if exact.count == 1 { return .resolved(exact[0]) }
        if exact.count > 1 { return .ambiguous(query: query, candidates: exact) }

        let partial = projects.filter { $0.name.lowercased().contains(needle) }
        switch partial.count {
        case 0: return .notFound(query: query)
        case 1: return .resolved(partial[0])
        default: return .ambiguous(query: query, candidates: partial)
        }
    }
}
