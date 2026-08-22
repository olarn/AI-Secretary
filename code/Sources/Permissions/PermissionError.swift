import Foundation

public enum PermissionError: Error, Equatable, Sendable {
    case toolNotAllowlisted(toolID: String, projectName: String)
}

extension PermissionError {
    public var reason: String {
        switch self {
        case let .toolNotAllowlisted(toolID, projectName):
            return "Tool '\(toolID)' is not in the allowlist for project '\(projectName)'."
        }
    }
}
