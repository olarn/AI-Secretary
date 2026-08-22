import FunctionalCore
import Foundation

public enum PermissionOutcome: Equatable, Sendable {
    case allowed
    case needsApproval(ApprovalRequest)
}

public typealias PermissionDecision = Either<PermissionError, PermissionOutcome>

public func noteToolOutsideAllowlist(
    _ request: ApprovalRequest
) -> Either<PermissionError, ApprovalRequest> {
    .right(
        request.project.allows(tool: request.toolID)
            ? request
            : request.steppingOutsideAllowlist()
    )
}

public func requireApproval(
    _ grants: PermissionGrants
) -> (ApprovalRequest) -> Either<PermissionError, PermissionOutcome> {
    { request in
        guard !noGrantMaySkipThis(request) else {
            return .right(.needsApproval(request))
        }
        return .right(
            grants.has(
                project: request.project,
                toolID: request.toolID,
                actionClass: request.actionClass
            )
                ? .allowed
                : .needsApproval(request)
        )
    }
}

public func noGrantMaySkipThis(_ request: ApprovalRequest) -> Bool {
    request.outsideAllowlist || !mayBeRemembered(request.actionClass)
}

public func decidePermission(_ grants: PermissionGrants) -> (ApprovalRequest) -> PermissionDecision {
    noteToolOutsideAllowlist >>> { $0.flatMap(requireApproval(grants))^ }
}
