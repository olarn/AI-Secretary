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

    public func add(_ project: Project) throws {
        projects.append(project)
        try store.save(projects)
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
