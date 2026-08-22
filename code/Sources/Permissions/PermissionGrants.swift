import FunctionalCore
import Foundation
import ProjectRegistry

public struct StandingGrant: Equatable, Hashable, Sendable, Comparable {
    public let projectPath: CanonicalPath

    public init(projectPath: CanonicalPath) {
        self.projectPath = projectPath
    }

    public init(project: Project) {
        self.init(projectPath: CanonicalPath(project.path))
    }

    public static func < (lhs: StandingGrant, rhs: StandingGrant) -> Bool {
        lhs.projectPath.value < rhs.projectPath.value
    }
}

public struct SessionGrant: Equatable, Hashable, Sendable {
    public let projectPath: CanonicalPath
    public let toolID: String
    public let actionClass: ActionClass

    public init(projectPath: CanonicalPath, toolID: String, actionClass: ActionClass) {
        self.projectPath = projectPath
        self.toolID = toolID
        self.actionClass = actionClass
    }
}

public struct PermissionGrants: Equatable, Sendable {
    private let session: Set<SessionGrant>
    private let standing: Set<StandingGrant>

    public init() {
        self.session = []
        self.standing = []
    }

    private init(session: Set<SessionGrant>, standing: Set<StandingGrant>) {
        self.session = session
        self.standing = standing
    }

    public func granting(
        project: Project,
        toolID: String,
        actionClass: ActionClass,
        lasting duration: GrantDuration = .session
    ) -> PermissionGrants {
        let path = CanonicalPath(project.path)
        switch duration {
        case .session:
            let only = SessionGrant(projectPath: path, toolID: toolID, actionClass: actionClass)
            return PermissionGrants(session: session.union([only]), standing: standing)
        case .always:
            return PermissionGrants(
                session: session,
                standing: standing.union([StandingGrant(projectPath: path)])
            )
        }
    }

    public func has(project: Project, toolID: String, actionClass: ActionClass) -> Bool {
        let path = CanonicalPath(project.path)
        let oneYesCoversTheWholeProject = standing.contains(StandingGrant(projectPath: path))
        return oneYesCoversTheWholeProject
            || session.contains(
                SessionGrant(projectPath: path, toolID: toolID, actionClass: actionClass)
            )
    }

    public var remembered: [StandingGrant] {
        standing.sorted()
    }

    public func adopting(remembered: [StandingGrant]) -> PermissionGrants {
        PermissionGrants(session: session, standing: Set(remembered))
    }

    public func forgetting(project: Project) -> PermissionGrants {
        let path = CanonicalPath(project.path)
        return PermissionGrants(
            session: session.filter { $0.projectPath != path },
            standing: standing.filter { $0.projectPath != path }
        )
    }
}

extension PermissionGrants {
    public static func granting(
        project: Project,
        toolID: String,
        actionClass: ActionClass,
        lasting duration: GrantDuration = .session
    ) -> (PermissionGrants) -> PermissionGrants {
        { grants in
            grants.granting(
                project: project,
                toolID: toolID,
                actionClass: actionClass,
                lasting: duration
            )
        }
    }
}
