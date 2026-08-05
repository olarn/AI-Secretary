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

/// First rail: notice when the tool isn't on the project's allowlist.
///
/// This used to refuse, on the reasoning that an allowlist miss is answered by
/// editing the allowlist rather than by asking a human to wave it through. In
/// the app that came out as a red *"denied by policy"* and no way forward from
/// the chat — the person couldn't even say yes to something they wanted. The
/// scratch project makes it worse: it allows only the agent, so with no project
/// registered, `/watch` and `/run` were refused outright rather than asked.
///
/// So the miss is now carried forward rather than fatal. It doesn't vanish:
/// `requireApproval` turns it into a question no grant can skip, and the card
/// says which list is being stepped past.
public func noteToolOutsideAllowlist(
    _ request: ApprovalRequest
) -> Either<PermissionError, ApprovalRequest> {
    .right(
        request.project.allows(tool: request.toolID)
            ? request
            : request.steppingOutsideAllowlist()
    )
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
        // Before the grants, not after. A grant is remembered per project and
        // tool for read-only work, so checking it first would let a tool the
        // allowlist never covered run unattended on the strength of one earlier
        // yes — which is the hole this rail exists to close.
        guard !request.outsideAllowlist else {
            return .right(.needsApproval(request))
        }
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
    noteToolOutsideAllowlist >>> { $0.flatMap(requireApproval(grants))^ }
}
