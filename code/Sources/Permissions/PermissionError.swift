import Foundation

/// Why a request was refused outright. Refusal is the failure rail of every
/// permission decision, so this is what sits on the left of `Either`.
///
/// Per-module error enum by design: `Permissions` owns its own failures and
/// never has to know about project loading or provider errors. Callers that
/// span layers map this into their own error type at the boundary.
public enum PermissionError: Error, Equatable, Sendable {
    /// The tool is not on the project's allowlist. Approval is not offered —
    /// the allowlist is the answer, not a prompt.
    case toolNotAllowlisted(toolID: String, projectName: String)
}

extension PermissionError {
    /// Human-readable refusal, for display next to the request that caused it.
    public var reason: String {
        switch self {
        case let .toolNotAllowlisted(toolID, projectName):
            return "Tool '\(toolID)' is not in the allowlist for project '\(projectName)'."
        }
    }
}
