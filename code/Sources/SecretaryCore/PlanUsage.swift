import Foundation

/// How much of the subscription's allowance is gone.
///
/// Separate from `SessionUsage`, which counts tokens this conversation moved.
/// This is the thing that actually stops work: a rate limit on the plan, shared
/// across every machine and every Claude Code session, not just this app's.
public struct PlanUsage: Equatable, Sendable {
    public struct Limit: Equatable, Sendable {
        public let label: String
        /// 0…1.
        public let fraction: Double
        /// When the window rolls over, as Claude Code phrased it. Kept as its
        /// own words rather than parsed into a `Date`: it already includes the
        /// user's timezone, and re-deriving it risks showing a wrong time.
        public let resets: String?

        public init(label: String, fraction: Double, resets: String?) {
            self.label = label
            self.fraction = fraction
            self.resets = resets
        }

        public var percentText: String { "\(Int((fraction * 100).rounded()))% used" }
    }

    public let limits: [Limit]
    public let checkedAt: Date

    public init(limits: [Limit], checkedAt: Date) {
        self.limits = limits
        self.checkedAt = checkedAt
    }
}

/// Reads the plan limits out of what `claude -p -- /usage` prints.
///
/// Text, not JSON — the CLI has no machine-readable form of this — so the parser
/// is deliberately forgiving and, more importantly, **silent when it doesn't
/// recognise something**. A wrong percentage is worse than no percentage: this
/// number is the one people use to decide whether to keep working, and the
/// format belongs to another program that can change it in any release.
public enum PlanUsageParser {
    /// Matches lines like
    /// `Current session: 25% used · resets Jul 31 at 1:59pm (Asia/Bangkok)`
    /// and `Current week (all models): 3% used · resets Aug 7 at 8:59am (…)`.
    private static let line = try? NSRegularExpression(
        pattern: #"^(Current [^:]+):\s*(\d{1,3})%\s*used(?:\s*·\s*resets\s+(.+?))?\s*$"#
    )

    public static func parse(_ text: String, now: Date = Date()) -> PlanUsage? {
        guard let line else { return nil }
        var limits: [PlanUsage.Limit] = []

        for raw in text.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = line.firstMatch(in: trimmed, range: range),
                  let labelRange = Range(match.range(at: 1), in: trimmed),
                  let percentRange = Range(match.range(at: 2), in: trimmed),
                  let percent = Int(trimmed[percentRange])
            else { continue }

            let resets = Range(match.range(at: 3), in: trimmed).map { String(trimmed[$0]) }
            limits.append(
                PlanUsage.Limit(
                    label: label(from: String(trimmed[labelRange])),
                    // Clamped: a plan that has gone over its allowance reports
                    // more than 100, and a bar past its end reads as a bug.
                    fraction: min(1, max(0, Double(percent) / 100)),
                    resets: resets
                )
            )
        }

        return limits.isEmpty ? nil : PlanUsage(limits: limits, checkedAt: now)
    }

    /// Shortens the CLI's wording for a narrow window, without inventing terms
    /// the user hasn't already seen.
    private static func label(from raw: String) -> String {
        raw
            .replacingOccurrences(of: "Current week (all models)", with: "This week")
            .replacingOccurrences(of: "Current week", with: "This week")
            .replacingOccurrences(of: "Current session", with: "Session")
    }
}
