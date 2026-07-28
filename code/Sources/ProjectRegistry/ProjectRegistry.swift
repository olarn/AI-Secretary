import FunctionalCore
import Foundation
import Observation

/// The single source of truth for which directories the assistant may work in.
///
/// The object owns exactly one piece of state — `projects` — and every question
/// about that list is answered by a pure function over it. Mutations return
/// `Either`, so a failed write surfaces as a value the caller must handle
/// instead of a `try?` that silently drops it.
@Observable
public final class ProjectRegistry {
    public private(set) var projects: [Project] = []

    @ObservationIgnored private let store: ProjectStoring

    public init(store: ProjectStoring = FileProjectStore()) {
        self.store = store
        // A registry that fails to load starts empty rather than refusing to
        // launch; the failure is not silently swallowed elsewhere because
        // every later write reports its own outcome.
        projects = store.load().getOrElse([])
    }

    /// Whether a project already points at the same directory.
    public func containsProject(atPath path: String) -> Bool {
        projectID(atPath: path)(projects).isDefined
    }

    /// Registers a project unless its directory is already registered, in
    /// which case the existing entry is kept and this reports `false`. This is
    /// what keeps "Add project…" from creating duplicate rows for one folder.
    @discardableResult
    public func add(_ project: Project) -> Either<ProjectStoreError, Bool> {
        guard !containsProject(atPath: project.path) else { return .right(false) }
        return commit(projects + [project]).map { true }^
    }

    /// Adds a tool to a project's allowlist and persists it.
    ///
    /// Called at the moment a human approves the capability, never on load — a
    /// project registered before a tool existed must not silently gain it.
    @discardableResult
    public func grant(tool: String, to projectID: UUID) -> Either<ProjectStoreError, Bool> {
        granting(tool: tool, to: projectID)(projects)
            .fold(
                { .right(false) },
                { updated in self.commit(updated).map { true }^ }
            )
    }

    @discardableResult
    public func remove(id: UUID) -> Either<ProjectStoreError, Void> {
        commit(projects.filter { $0.id != id })
    }

    public func project(id: UUID) -> Option<Project> {
        Option.fromOptional(projects.first { $0.id == id })
    }

    /// Resolves a project reference from user text. See `resolveProject`.
    public func resolve(query: Option<String>) -> ProjectResolution {
        resolveProject(in: projects)(query)
    }

    /// The one place `projects` is assigned: persist first, and only adopt the
    /// new list if the write succeeded, so what is on screen always matches
    /// what is on disk.
    private func commit(_ updated: [Project]) -> Either<ProjectStoreError, Void> {
        store.save(updated)
            .map { self.projects = updated }^
    }
}

// MARK: - Questions about a project list, as pure functions

/// The ID of the project registered at `path`, comparing standardised paths so
/// "/a/b" and "/a/b/" are one place.
public func projectID(atPath path: String) -> ([Project]) -> Option<UUID> {
    { projects in
        let target = Project.normalize(path)
        return Option.fromOptional(projects.first { $0.normalizedPath == target }?.id)
    }
}

/// The list with `tool` added to one project's allowlist, or `none` when that
/// changes nothing — either the project is unknown or it already had the tool.
public func granting(tool: String, to projectID: UUID) -> ([Project]) -> Option<[Project]> {
    { projects in
        Option.fromOptional(projects.firstIndex { $0.id == projectID })
            .flatMap { index in
                projects[index].granting(tool: tool).map { granted in
                    var updated = projects
                    updated[index] = granted
                    return updated
                }
            }^
    }
}
