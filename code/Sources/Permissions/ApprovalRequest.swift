import Foundation
import ProjectRegistry

public struct ApprovalRequest: Equatable, Sendable {
    public let taskID: String
    public let toolID: String
    public let actionClass: ActionClass
    public let project: Project
    public let commandSummary: String
    public let rationale: String
    public let outsideAllowlist: Bool

    public init(
        taskID: String,
        toolID: String,
        actionClass: ActionClass,
        project: Project,
        commandSummary: String,
        rationale: String,
        outsideAllowlist: Bool = false
    ) {
        self.taskID = taskID
        self.toolID = toolID
        self.actionClass = actionClass
        self.project = project
        self.commandSummary = commandSummary
        self.rationale = rationale
        self.outsideAllowlist = outsideAllowlist
    }

    public func steppingOutsideAllowlist() -> ApprovalRequest {
        ApprovalRequest(
            taskID: taskID,
            toolID: toolID,
            actionClass: actionClass,
            project: project,
            commandSummary: commandSummary,
            rationale: rationale,
            outsideAllowlist: true
        )
    }
}
