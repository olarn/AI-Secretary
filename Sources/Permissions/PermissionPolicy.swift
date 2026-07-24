import Foundation
import ProjectRegistry

/// A concrete thing the assistant wants to do, described well enough that a
/// human can decide on it without reading code.
public struct ApprovalRequest: Equatable, Sendable {
    public let taskID: String
    public let toolID: String
    public let actionClass: ActionClass
    public let project: Project
    /// Exact command that will run, for display. Never re-parsed to execute.
    public let commandSummary: String
    public let rationale: String

    public init(
        taskID: String,
        toolID: String,
        actionClass: ActionClass,
        project: Project,
        commandSummary: String,
        rationale: String
    ) {
        self.taskID = taskID
        self.toolID = toolID
        self.actionClass = actionClass
        self.project = project
        self.commandSummary = commandSummary
        self.rationale = rationale
    }
}

public enum PermissionDecision: Equatable, Sendable {
    /// Nothing stands in the way; run it.
    case allowed
    /// A human must confirm before this runs.
    case needsApproval(ApprovalRequest)
    /// Refused outright by policy — approval is not offered.
    case denied(reason: String)
}

public protocol PermissionPolicy: AnyObject {
    func evaluate(_ request: ApprovalRequest) -> PermissionDecision
    /// Records that a human approved this project/tool pair, so later
    /// read-only work in the same directory doesn't re-prompt.
    func recordApproval(projectID: UUID, toolID: String)
    func hasApproval(projectID: UUID, toolID: String) -> Bool
}

/// Default policy: the tool must be allow-listed on the project, the first use
/// of a project/tool pair always asks (per the "accessing a new directory"
/// rule), and anything with side effects asks every single time.
public final class DefaultPermissionPolicy: PermissionPolicy {
    private struct ApprovalKey: Hashable {
        let projectID: UUID
        let toolID: String
    }

    private var granted: Set<ApprovalKey> = []

    public init() {}

    public func evaluate(_ request: ApprovalRequest) -> PermissionDecision {
        guard request.project.allows(tool: request.toolID) else {
            return .denied(
                reason: "Tool '\(request.toolID)' is not in the allowlist for project '\(request.project.name)'."
            )
        }

        guard request.actionClass.canRunUnattended else {
            return .needsApproval(request)
        }

        return hasApproval(projectID: request.project.id, toolID: request.toolID)
            ? .allowed
            : .needsApproval(request)
    }

    public func recordApproval(projectID: UUID, toolID: String) {
        granted.insert(ApprovalKey(projectID: projectID, toolID: toolID))
    }

    public func hasApproval(projectID: UUID, toolID: String) -> Bool {
        granted.contains(ApprovalKey(projectID: projectID, toolID: toolID))
    }
}
