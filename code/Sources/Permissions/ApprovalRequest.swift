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
    /// Whether the project's allowlist covers this tool.
    ///
    /// It used to be the difference between asking and refusing. Now it is
    /// something the card has to *say*, because agreeing to this is agreeing to
    /// more than the one action: the person is stepping past a list they set.
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

    /// The same request, marked as reaching past the project's allowlist.
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
