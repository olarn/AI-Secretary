import FunctionalCore
import Foundation

public struct Project: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let path: String
    public let summary: Option<String>
    public let allowedTools: [String]
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

    public func granting(tool: String) -> Option<Project> {
        let grantingWouldChangeNothing = allowedTools.contains(tool)
        guard !grantingWouldChangeNothing else { return .none() }
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

    public static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public var normalizedPath: String { Project.normalize(path) }
}

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

public enum ProjectResolution: Equatable, Sendable {
    case resolved(Project)
    case notFound(query: String)
    case ambiguous(query: String, candidates: [Project])
    case needsSelection(candidates: [Project])
}

public func resolveProject(
    in projects: [Project]
) -> (Option<String>) -> ProjectResolution {
    { query in
        let needle = query
            .map { $0.trimmingCharacters(in: .whitespaces) }^
            .filter { !$0.isEmpty }^

        return needle.fold(
            { defaultProject(in: projects) },
            { matchProjectByNameNeverByGuessingAPath(in: projects, named: $0) }
        )
    }
}

private func defaultProject(in projects: [Project]) -> ProjectResolution {
    projects.count == 1
        ? .resolved(projects[0])
        : .needsSelection(candidates: projects)
}

private func matchProjectByNameNeverByGuessingAPath(
    in projects: [Project],
    named query: String
) -> ProjectResolution {
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
