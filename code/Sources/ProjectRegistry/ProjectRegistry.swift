import FunctionalCore
import Foundation
import Observation

@Observable
public final class ProjectRegistry {
    public private(set) var projects: [Project] = []

    @ObservationIgnored private let store: ProjectStoring

    public init(store: ProjectStoring = FileProjectStore()) {
        self.store = store
        projects = store.load().getOrElse([])
    }

    public func containsProject(atPath path: String) -> Bool {
        projectID(atPath: path)(projects).isDefined
    }

    @discardableResult
    public func add(_ project: Project) -> Either<ProjectStoreError, Bool> {
        let thatDirectoryIsAlreadyRegistered = containsProject(atPath: project.path)
        guard !thatDirectoryIsAlreadyRegistered else { return .right(false) }
        return commit(projects + [project]).map { true }^
    }

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

    public func resolve(query: Option<String>) -> ProjectResolution {
        resolveProject(in: projects)(query)
    }

    private func commit(_ updated: [Project]) -> Either<ProjectStoreError, Void> {
        store.save(updated)
            .map { self.projects = updated }^
    }
}

public func projectID(atPath path: String) -> ([Project]) -> Option<UUID> {
    { projects in
        let target = Project.normalize(path)
        return Option.fromOptional(projects.first { $0.normalizedPath == target }?.id)
    }
}

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
