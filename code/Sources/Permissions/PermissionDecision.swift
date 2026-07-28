import FunctionalCore
import Foundation

/// What may happen to a request that policy did not refuse.
public enum PermissionOutcome: Equatable, Sendable {
    /// Nothing stands in the way; run it.
    case allowed
    /// A human must confirm before this runs.
    case needsApproval(ApprovalRequest)
}

/// The result of evaluating a request: refusal on the left rail, a runnable
/// outcome on the right. `Either` rather than `throws` so a decision is an
/// ordinary value — storable in state, comparable in tests, composable with
/// the next step without a `do`/`catch` around every call site.
public typealias PermissionDecision = Either<PermissionError, PermissionOutcome>

// MARK: - The rails

/// First rail: the tool must be allow-listed on the project. Failing here is a
/// refusal, not a prompt — per the "accessing a new directory" rule, an
/// allowlist miss is answered by editing the allowlist, not by asking a human
/// to wave it through.
public func requireAllowlistedTool(
    _ request: ApprovalRequest
) -> Either<PermissionError, ApprovalRequest> {
    request.project.allows(tool: request.toolID)
        ? .right(request)
        : .left(.toolNotAllowlisted(toolID: request.toolID, projectName: request.project.name))
}

/// Second rail: decide whether this request can run unattended.
///
/// Anything with side effects asks every single time. Read-only work asks the
/// first time a project/tool pair is used and runs unattended after that.
///
/// Curried on the grants so it composes as `flatMap(requireApproval(grants))`.
public func requireApproval(
    _ grants: PermissionGrants
) -> (ApprovalRequest) -> Either<PermissionError, PermissionOutcome> {
    { request in
        guard request.actionClass.canRunUnattended else {
            return .right(.needsApproval(request))
        }
        return .right(
            grants.has(projectID: request.project.id, toolID: request.toolID)
                ? .allowed
                : .needsApproval(request)
        )
    }
}

// MARK: - The chain

/// The whole policy, as a pure function of the grants and the request.
///
/// Curried so the grants can be bound once and the resulting
/// `(ApprovalRequest) -> PermissionDecision` passed around point-free.
public func decidePermission(_ grants: PermissionGrants) -> (ApprovalRequest) -> PermissionDecision {
    requireAllowlistedTool >>> { $0.flatMap(requireApproval(grants))^ }
}
