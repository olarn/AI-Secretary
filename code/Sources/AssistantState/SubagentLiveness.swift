import Foundation

public enum Liveness: Equatable, Sendable {
    case running
    case quiet(TimeInterval)
    case presumedLost
}

public enum SubagentWatch: Sendable {
    public static let quietAfter: TimeInterval = 30

    public static let presumedLostAfter: TimeInterval = 5 * 60
}

public func subagentLiveness(lastEventAt: Date, now: Date = Date()) -> Liveness {
    let silence = now.timeIntervalSince(lastEventAt)
    guard silence >= SubagentWatch.quietAfter else { return .running }
    guard silence < SubagentWatch.presumedLostAfter else { return .presumedLost }
    return .quiet(silence)
}
