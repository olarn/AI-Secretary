import Foundation
import AssistantState
import LLMProvider

/// A sub-agent that is running now, and when it last said anything.
///
/// The pair exists because neither half answers the question on its own: the
/// task says *what* is happening, the timestamp says whether it is still
/// happening at all. Keeping them together means the header cannot show a live
/// description beside a stale liveness, which is the failure this replaces —
/// working and dead looked identical.
public struct RunningSubagent: Equatable, Sendable {
    public let task: SubagentTask
    /// Stamped from the last event that mentioned this task, not from when it
    /// started: the whole point is elapsed silence.
    public let lastEventAt: Date

    public init(task: SubagentTask, lastEventAt: Date) {
        self.task = task
        self.lastEventAt = lastEventAt
    }

    /// A new reading of the same sub-agent. `-ing` and returning a value rather
    /// than mutating, per the domain rules.
    public func hearing(_ task: SubagentTask, at moment: Date) -> RunningSubagent {
        RunningSubagent(task: task, lastEventAt: moment)
    }

    /// How it looks from outside right now. `now` last and defaulted, so tests
    /// pin it and production never types one.
    public func liveness(now: Date = Date()) -> Liveness {
        subagentLiveness(lastEventAt: lastEventAt, now: now)
    }

    /// What the header says about it. In here rather than in the view, because
    /// it is a decision and `AISecretaryApp` is invisible to coverage.
    public func badgeText(now: Date = Date()) -> String {
        subagentBadgeText(
            detail: task.detail.isEmpty ? task.kind : task.detail,
            lastTool: task.lastTool.toOptional(),
            liveness: liveness(now: now)
        )
    }
}

/// One line for the header: what it is doing, and whether it is still answering.
///
/// **Never says it failed.** Nothing on this side can know that — a sub-agent
/// running one slow tool call looks exactly like one whose process died, and the
/// only honest thing to report is how long it has been since it last said
/// anything. Wording that guessed would be wrong about half the time and would
/// be believed every time.
///
/// The tool name is worth carrying: "quiet" next to `Bash` reads as a long
/// command, which is the common case and stops the silence looking like a fault.
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
