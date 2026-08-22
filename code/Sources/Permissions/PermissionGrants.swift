import FunctionalCore
import Foundation

public struct StandingGrant: Equatable, Hashable, Sendable {
    public let projectID: UUID
    public let toolID: String
    public let actionClass: ActionClass

    public init(projectID: UUID, toolID: String, actionClass: ActionClass) {
        self.projectID = projectID
        self.toolID = toolID
        self.actionClass = actionClass
    }
}

public struct PermissionGrants: Equatable, Sendable {
    private let session: Set<StandingGrant>
    private let standing: Set<StandingGrant>

    public init() {
        self.session = []
        self.standing = []
    }

    private init(session: Set<StandingGrant>, standing: Set<StandingGrant>) {
        self.session = session
        self.standing = standing
    }

    public func granting(
        projectID: UUID,
        toolID: String,
        actionClass: ActionClass,
        lasting duration: GrantDuration = .session
    ) -> PermissionGrants {
        let key = StandingGrant(projectID: projectID, toolID: toolID, actionClass: actionClass)
        switch duration {
        case .session:
            return PermissionGrants(session: session.union([key]), standing: standing)
        case .always:
            return PermissionGrants(session: session, standing: standing.union([key]))
        }
    }

    public func has(projectID: UUID, toolID: String, actionClass: ActionClass) -> Bool {
        let key = StandingGrant(projectID: projectID, toolID: toolID, actionClass: actionClass)
        return session.contains(key) || standing.contains(key)
    }

    public var remembered: [StandingGrant] {
        standing.sorted {
            ($0.projectID.uuidString, $0.toolID, $0.actionClass.rawValue)
                < ($1.projectID.uuidString, $1.toolID, $1.actionClass.rawValue)
        }
    }

    public func adopting(remembered: [StandingGrant]) -> PermissionGrants {
        PermissionGrants(session: session, standing: Set(remembered))
    }

    public func forgetting(projectID: UUID) -> PermissionGrants {
        PermissionGrants(
            session: session.filter { $0.projectID != projectID },
            standing: standing.filter { $0.projectID != projectID }
        )
    }
}

extension PermissionGrants {
    public static func granting(
        projectID: UUID,
        toolID: String,
        actionClass: ActionClass,
        lasting duration: GrantDuration = .session
    ) -> (PermissionGrants) -> PermissionGrants {
        { grants in
            grants.granting(
                projectID: projectID,
                toolID: toolID,
                actionClass: actionClass,
                lasting: duration
            )
        }
    }
}
