import FunctionalCore
import Foundation

// MARK: - Imperative edge
//
// Everything below is a boundary adapter, not domain logic. `SecretaryCore`
// still holds permissions in a reference-typed object and mutates it in place;
// until that target moves onto `PermissionGrants` + `decide`, this shim keeps
// the old surface working over the pure core. Delete it once `Secretary` owns
// its grants as part of its observable state.

/// The pre-`Either` shape of a decision, kept for callers that still switch on
/// an enum. Prefer `PermissionDecision` (`Either<PermissionError, PermissionOutcome>`).
public enum PolicyDecision: Equatable, Sendable {
    case allowed
    case needsApproval(ApprovalRequest)
    case denied(reason: String)
}

extension Either where A == PermissionError, B == PermissionOutcome {
    /// Collapse the two rails back into the flat enum the imperative edge wants.
    public func toPolicyDecision() -> PolicyDecision {
        fold(
            { error in .denied(reason: error.reason) },
            { outcome in
                switch outcome {
                case .allowed: return .allowed
                case let .needsApproval(request): return .needsApproval(request)
                }
            }
        )
    }
}

public protocol PermissionPolicy: AnyObject {
    func evaluate(_ request: ApprovalRequest) -> PolicyDecision
    /// Records that a human approved this project/tool pair, so later
    /// read-only work in the same directory doesn't re-prompt.
    func recordApproval(projectID: UUID, toolID: String)
    func hasApproval(projectID: UUID, toolID: String) -> Bool
}

/// Mutable box around the immutable `PermissionGrants`. It holds state and
/// delegates every actual decision to `decide` — there is no policy logic here.
public final class DefaultPermissionPolicy: PermissionPolicy {
    private var grants = PermissionGrants()

    public init() {}

    public func evaluate(_ request: ApprovalRequest) -> PolicyDecision {
        decidePermission(grants)(request).toPolicyDecision()
    }

    public func recordApproval(projectID: UUID, toolID: String) {
        grants = grants |> PermissionGrants.granting(projectID: projectID, toolID: toolID)
    }

    public func hasApproval(projectID: UUID, toolID: String) -> Bool {
        grants.has(projectID: projectID, toolID: toolID)
    }
}
