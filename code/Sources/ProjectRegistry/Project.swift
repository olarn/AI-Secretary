import FunctionalCore
import Foundation

/// An explicitly registered project. Coding work only ever runs against one
/// of these — a path is never inferred from a project name typed in chat.
///
/// Not `Codable`: `Option` cannot be. Persistence goes through `ProjectDTO`,
/// which keeps the on-disk JSON byte-identical to what earlier versions wrote.
public struct Project: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let path: String
    /// Free-text note about the project. Named `summary` in the domain because
    /// `description` on a struct reads as `CustomStringConvertible`; the JSON
    /// key stays `description` so existing files still load.
    public let summary: Option<String>
    /// Tool identifiers this project may use, e.g. "git.readOnly".
    public let allowedTools: [String]
    /// Action identifiers this project may perform, e.g. "read".
    public let allowedActions: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        summary: Option<String> = .none(),
        allowedTools: [String] = [],
        allowedActions: [String] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.summary = summary
        self.allowedTools = allowedTools
        self.allowedActions = allowedActions
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public func allows(tool: String) -> Bool { allowedTools.contains(tool) }

    /// Absent when the tool was already there, so a caller can tell "granted"
    /// from "no change" without comparing arrays.
    ///
    /// Built field by field rather than by copying and mutating: every stored
    /// property is a `let`, so "one more tool" is a new value.
    public func granting(tool: String) -> Option<Project> {
        guard !allowedTools.contains(tool) else { return .none() }
        return .some(
            Project(
                id: id,
                name: name,
                path: path,
                summary: summary,
                allowedTools: allowedTools + [tool],
                allowedActions: allowedActions
            )
        )
    }

    /// Paths compared after standardising, so "/a/b" and "/a/b/" are one place.
    public static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public var normalizedPath: String { Project.normalize(path) }
}

// MARK: - Persistence edge

/// The on-disk shape: Swift `Optional` and `Codable`, mirroring the JSON that
/// shipped before this type split in two.
public struct ProjectDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var description: String?
    public var allowedTools: [String]
    public var allowedActions: [String]
}

extension Project {
    public init(_ dto: ProjectDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            path: dto.path,
            summary: Option.fromOptional(dto.description),
            allowedTools: dto.allowedTools,
            allowedActions: dto.allowedActions
        )
    }

    public var dto: ProjectDTO {
        ProjectDTO(
            id: id,
            name: name,
            path: path,
            description: summary.toOptional(),
            allowedTools: allowedTools,
            allowedActions: allowedActions
        )
    }
}

/// Outcome of resolving a user-supplied project reference.
public enum ProjectResolution: Equatable, Sendable {
    case resolved(Project)
    /// **Never fall back to guessing a filesystem path from the query.**
    case notFound(query: String)
    case ambiguous(query: String, candidates: [Project])
    case needsSelection(candidates: [Project])
}

// MARK: - Resolution, as a pure function

/// Resolves a project reference from user text against a list of projects.
///
/// A free function curried on the list, so it is testable without building a
/// registry and reusable anywhere a candidate list exists. Matching is by name
/// only — a filesystem path is never derived from the query, so an unregistered
/// name resolves to `.notFound` rather than a guessed directory.
public func resolveProject(
    in projects: [Project]
) -> (Option<String>) -> ProjectResolution {
    { query in
        let needle = query
            .map { $0.trimmingCharacters(in: .whitespaces) }^
            .filter { !$0.isEmpty }^

        return needle.fold(
            { defaultProject(in: projects) },
            { matchProject(in: projects, named: $0) }
        )
    }
}

private func defaultProject(in projects: [Project]) -> ProjectResolution {
    projects.count == 1
        ? .resolved(projects[0])
        : .needsSelection(candidates: projects)
}

private func matchProject(in projects: [Project], named query: String) -> ProjectResolution {
    let needle = query.lowercased()
    let exact = projects.filter { $0.name.lowercased() == needle }
    let candidates = exact.isEmpty
        ? projects.filter { $0.name.lowercased().contains(needle) }
        : exact

    switch candidates.count {
    case 0: return .notFound(query: query)
    case 1: return .resolved(candidates[0])
    default: return .ambiguous(query: query, candidates: candidates)
    }
}
