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
