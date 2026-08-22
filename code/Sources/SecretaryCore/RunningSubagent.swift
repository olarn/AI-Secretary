import Foundation
import AssistantState
import LLMProvider

public struct RunningSubagent: Equatable, Sendable {
    public let task: SubagentTask
    public let lastEventAt: Date

    public init(task: SubagentTask, lastEventAt: Date) {
        self.task = task
        self.lastEventAt = lastEventAt
    }

    public func hearing(_ task: SubagentTask, at moment: Date) -> RunningSubagent {
        RunningSubagent(task: task, lastEventAt: moment)
    }

    public func liveness(now: Date = Date()) -> Liveness {
        subagentLiveness(lastEventAt: lastEventAt, now: now)
    }

    public func badgeText(now: Date = Date()) -> String {
        subagentBadgeText(
            detail: task.detail.isEmpty ? task.kind : task.detail,
            lastTool: task.lastTool.toOptional(),
            liveness: liveness(now: now)
        )
    }
}

public func subagentBadgeText(
    detail: String,
    lastTool: String?,
    liveness: Liveness
) -> String {
    let what = lastTool.map { "\(detail) · \($0)" } ?? detail
    switch liveness {
    case .running:
        return what
    case .quiet(let silence):
        return "\(what) — quiet \(Int(silence))s"
    case .presumedLost:
        return "\(what) — nothing for a while"
    }
}
