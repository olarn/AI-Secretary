import Foundation

/// Why a request was refused outright. Refusal is the failure rail of every
/// permission decision, so this is what sits on the left of `Either`.
///
/// Per-module error enum by design: `Permissions` owns its own failures and
/// never has to know about project loading or provider errors. Callers that
/// span layers map this into their own error type at the boundary.
/// No rail produces one today: the allowlist miss that used to land here is now
/// a question instead (`noteToolOutsideAllowlist`), because a refusal the person
/// can't answer is worse than a decision they can. The rail is kept rather than
/// removed — a policy that can only ever say yes-or-ask has nowhere to put the
/// rule that genuinely must not be waved through, and adding the left back
/// later is a worse change than leaving room for it.
public enum PermissionError: Error, Equatable, Sendable {
    /// Unused since the allowlist started asking. Left in place as the shape a
    /// real refusal would take, and because `reason` is what the chat would
    /// print if one ever occurred.
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
