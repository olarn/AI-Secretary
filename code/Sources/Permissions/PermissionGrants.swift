import FunctionalCore
import Foundation

/// One project/tool pair a human has approved, as a value something else can
/// write down.
public struct StandingGrant: Equatable, Hashable, Sendable {
    public let projectID: UUID
    public let toolID: String
    /// **Part of the key, not a label.** One tool id serves more than one kind
    /// of work — `file.readOnly` both reads a file and, as `.externalNetwork`,
    /// sends one to the model — so a grant keyed on the tool alone turns "yes,
    /// read it" into "yes, send it". Measured: dropping this made
    /// `testApprovingReadOnlyDoesNotAuthoriseSending` go green in the wrong
    /// direction.
    public let actionClass: ActionClass

    public init(projectID: UUID, toolID: String, actionClass: ActionClass) {
        self.projectID = projectID
        self.toolID = toolID
        self.actionClass = actionClass
    }
}

/// Which project/tool pairs a human has already approved, and for how long.
///
/// This is a value, not a mutable store: `granting` returns a new set rather
/// than mutating in place. That is what lets grants live inside the single
/// observable state alongside everything else the UI renders — there is no
/// second copy hidden in a class that can drift out of sync with the view.
///
/// Two sets, not one, and the split is the whole of Sprint 15: `session` dies
/// with the conversation, `standing` is written to disk and read back on the
/// next launch. A lookup asks both, because from the caller's side "have they
/// agreed to this" has one answer.
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

    /// Only the half that outlives the app. What the store writes, and the only
    /// thing it may write — a session grant reaching disk would be the bug this
    /// split exists to make impossible.
    public var remembered: [StandingGrant] {
        standing.sorted {
            ($0.projectID.uuidString, $0.toolID, $0.actionClass.rawValue)
                < ($1.projectID.uuidString, $1.toolID, $1.actionClass.rawValue)
        }
    }

    /// The same grants with what was read from disk put back.
    ///
    /// Replaces rather than merges the standing half: the file is the record of
    /// what is remembered, so a pair deleted from it is a pair the person took
    /// back.
    public func adopting(remembered: [StandingGrant]) -> PermissionGrants {
        PermissionGrants(session: session, standing: Set(remembered))
    }

    /// The same grants with one project forgotten, both halves.
    ///
    /// For deleting a project: leaving its grants behind means a folder
    /// registered again later — same path, new id — is safe, but a *reused* id
    /// never is, and the row nobody can see is the one nobody revokes.
    public func forgetting(projectID: UUID) -> PermissionGrants {
        PermissionGrants(
            session: session.filter { $0.projectID != projectID },
            standing: standing.filter { $0.projectID != projectID }
        )
    }
}

extension PermissionGrants {
    /// Curried form, so a grant can be applied down a pipeline:
    /// `grants |> PermissionGrants.granting(projectID: id, toolID: tool)`
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
