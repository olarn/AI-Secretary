import Foundation

/// An explicitly registered project. Coding work only ever runs against one
/// of these — a path is never inferred from a project name typed in chat.
public struct Project: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var path: String
    public var description: String?
    /// Tool identifiers this project may use, e.g. "git.readOnly".
    public var allowedTools: [String]
    /// Action identifiers this project may perform, e.g. "read".
    public var allowedActions: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        description: String? = nil,
        allowedTools: [String] = [],
        allowedActions: [String] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.description = description
        self.allowedTools = allowedTools
        self.allowedActions = allowedActions
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public func allows(tool: String) -> Bool { allowedTools.contains(tool) }
}

/// Outcome of resolving a user-supplied project reference.
public enum ProjectResolution: Equatable, Sendable {
    /// Exactly one project matched — safe to proceed.
    case resolved(Project)
    /// Nothing matched. Never fall back to guessing a filesystem path.
    case notFound(query: String)
    /// Several matched; the user must pick one explicitly.
    case ambiguous(query: String, candidates: [Project])
    /// No reference was given and there is no single obvious default.
    case needsSelection(candidates: [Project])
}
