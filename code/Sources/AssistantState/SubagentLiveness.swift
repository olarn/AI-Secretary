import Foundation

/// How a running sub-agent looks from outside, judged only on when it last said
/// anything.
///
/// Three states rather than a `Bool`, because "still going" and "I have not
/// heard anything for a while" are different things to a person deciding whether
/// to wait — and collapsing them is exactly the complaint this was written for:
/// working and dead looked identical.
public enum Liveness: Equatable, Sendable {
    case running
    /// Nothing for a while. Carries how long, because "quiet" without a duration
    /// is the same non-answer as showing nothing at all.
    case quiet(TimeInterval)
    /// Long enough that it probably is not coming back.
    case presumedLost
}

public enum SubagentWatch: Sendable {
    /// Claude Code sends a `task_progress` line per step of the sub-agent's
    /// work. Measured on 2026-08-18 (CLI 2.1.234): a whole trivial sub-agent ran
    /// in 5.2s with a progress line at 2.7s. So a gap of half a minute is
    /// already unusual, while anything shorter would flicker on a sub-agent
    /// thinking between two tool calls.
    public static let quietAfter: TimeInterval = 30

    /// Not "it failed" — nothing here can know that. It is the point past which
    /// the honest thing is to stop implying work is under way. Five minutes is
    /// long enough for a slow single tool call (a test suite, a big grep) to
    /// finish and report, and short enough to notice within one coffee.
    public static let presumedLostAfter: TimeInterval = 5 * 60
}

/// What to say about a sub-agent that last spoke at `lastEventAt`.
///
/// `now` is last and defaulted — the repo's idiom for keeping a time-dependent
/// decision deterministic, so tests pass a fixed date and production never types
/// one.
///
/// A clock that has gone backwards (an event stamped in the future) reads as
/// `.running` rather than as a negative quiet time, because the only honest
/// reading of "it spoke a moment from now" is that it is alive.
public func subagentLiveness(lastEventAt: Date, now: Date = Date()) -> Liveness {
    let silence = now.timeIntervalSince(lastEventAt)
    guard silence >= SubagentWatch.quietAfter else { return .running }
    guard silence < SubagentWatch.presumedLostAfter else { return .presumedLost }
    return .quiet(silence)
}
