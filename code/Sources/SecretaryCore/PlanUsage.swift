import Foundation

/// How much of the subscription's allowance is gone.
///
/// Separate from `SessionUsage`, which counts tokens this conversation moved.
/// This is the thing that actually stops work: a rate limit on the plan, shared
/// across every machine and every Claude Code session, not just this app's.
///
/// Shaped after the Usage panel in the Claude app, because that is the layout
/// the user already reads. Two of its sections cannot be filled from here: the
/// plan's name and the usage-credit figures are not in anything the CLI prints.
public struct PlanUsage: Equatable, Sendable {
    /// Which window a limit belongs to, so the view can group them the way the
    /// Claude app does instead of listing three unrelated bars.
    public enum Scope: Equatable, Sendable {
        case session
        case week
    }

    public struct Limit: Equatable, Sendable {
        public let scope: Scope
        /// What to call it in the list: "Current session", "All models", "Fable".
        public let name: String
        /// 0…1.
        public let fraction: Double
        /// When the window rolls over, exactly as Claude Code phrased it. Kept
        /// verbatim as the fallback, because it already carries the user's
        /// timezone and re-deriving it risks showing the wrong time.
        public let resetsText: String?
        /// The same instant, when it could be read. Absent is normal, not a
        /// failure — the weekly per-model line carries no reset at all.
        public let resetsAt: Date?

        public init(
            scope: Scope,
            name: String,
            fraction: Double,
            resetsText: String?,
            resetsAt: Date?
        ) {
            self.scope = scope
            self.name = name
            self.fraction = fraction
            self.resetsText = resetsText
            self.resetsAt = resetsAt
        }

        public var percentText: String { "\(Int((fraction * 100).rounded()))% used" }

        /// "Resets in 27 min" close up, the CLI's own words otherwise. Relative
        /// only within a day: past that, "in 6 days" is less useful than the
        /// date the CLI already spelled out with a timezone on it.
        public func resetDescription(now: Date = Date()) -> String? {
            guard let resetsAt, resetsAt > now,
                  resetsAt.timeIntervalSince(now) < 86_400
            else { return resetsText.map { "Resets \($0)" } }
            return "Resets in \(UsageFormat.duration(until: resetsAt, from: now))"
        }
    }

    /// A recent stretch of work, as Claude Code counts it locally.
    public struct Activity: Equatable, Sendable {
        /// "Last 24h", "Last 7d" — the CLI's own wording.
        public let period: String
        public let requests: Int
        public let sessions: Int
        /// The behaviour lines under it, e.g. "84% of your usage was at >150k
        /// context". Kept verbatim: they explain *why* the bars are where they
        /// are, which is the only reason this section is worth the space.
        public let notes: [String]

        public init(period: String, requests: Int, sessions: Int, notes: [String]) {
            self.period = period
            self.requests = requests
            self.sessions = sessions
            self.notes = notes
        }
    }

    public let limits: [Limit]
    public let activity: [Activity]
    /// "Max", "Pro" — the subscription tier, title-cased from what
    /// `claude auth status` reports. Absent if it could not be read.
    public let planName: String?
    public let checkedAt: Date

    public init(
        limits: [Limit],
        activity: [Activity] = [],
        planName: String? = nil,
        checkedAt: Date
    ) {
        self.limits = limits
        self.activity = activity
        self.planName = planName
        self.checkedAt = checkedAt
    }

    public func named(_ planName: String?) -> PlanUsage {
        PlanUsage(limits: limits, activity: activity, planName: planName, checkedAt: checkedAt)
    }

    /// The CLI's own disclaimer, shown with the counts because it changes what
    /// they mean: they are this machine's sessions, not the account's.
    public static let activityNote =
        "Counted from sessions on this Mac only — other devices and claude.ai aren't included."

    public var session: [Limit] { limits.filter { $0.scope == .session } }
    public var weekly: [Limit] { limits.filter { $0.scope == .week } }
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

            let label = String(trimmed[labelRange])
            let resets = Range(match.range(at: 3), in: trimmed).map { String(trimmed[$0]) }
            limits.append(
                PlanUsage.Limit(
                    scope: label.hasPrefix("Current week") ? .week : .session,
                    name: displayName(for: label),
                    // Clamped: a plan that has gone over its allowance reports
                    // more than 100, and a bar past its end reads as a bug.
                    fraction: min(1, max(0, Double(percent) / 100)),
                    resetsText: resets,
                    resetsAt: resets.flatMap { resetDate(from: $0, now: now) }
                )
            )
        }

        return limits.isEmpty
            ? nil
            : PlanUsage(limits: limits, activity: activity(in: text), checkedAt: now)
    }

    /// Matches `Last 24h · 532 requests · 11 sessions`.
    private static let periodLine = try? NSRegularExpression(
        pattern: #"^(Last [^·]+)·\s*([\d,]+)\s+requests\s*·\s*([\d,]+)\s+sessions\s*$"#
    )

    /// The "what's contributing" block: how much work went through this machine
    /// recently, and what shape it had.
    ///
    /// The notes are the indented lines under each period. `Top skills` and
    /// `Top plugins` are deliberately dropped — they name what the user has been
    /// working on, which is more than a usage gauge needs to put on screen.
    static func activity(in text: String) -> [PlanUsage.Activity] {
        guard let periodLine else { return [] }
        var found: [PlanUsage.Activity] = []

        for raw in text.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = periodLine.firstMatch(in: trimmed, range: range),
               let periodRange = Range(match.range(at: 1), in: trimmed),
               let requestsRange = Range(match.range(at: 2), in: trimmed),
               let sessionsRange = Range(match.range(at: 3), in: trimmed) {
                found.append(
                    PlanUsage.Activity(
                        period: String(trimmed[periodRange]).trimmingCharacters(in: .whitespaces),
                        requests: number(String(trimmed[requestsRange])),
                        sessions: number(String(trimmed[sessionsRange])),
                        notes: []
                    )
                )
                continue
            }
            // Indented, so it belongs to the period above it.
            guard raw.hasPrefix("  "), !trimmed.isEmpty, let last = found.popLast() else { continue }
            let keep = trimmed.hasPrefix("Top skills") || trimmed.hasPrefix("Top plugins")
                ? last.notes
                : last.notes + [trimmed]
            found.append(
                PlanUsage.Activity(
                    period: last.period, requests: last.requests,
                    sessions: last.sessions, notes: keep
                )
            )
        }
        return found
    }

    private static func number(_ text: String) -> Int {
        Int(text.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    /// The CLI says "Current week (all models)"; under a "Weekly limits" heading
    /// that reads as a stutter. These names match the Claude app's.
    static func displayName(for label: String) -> String {
        if label == "Current week (all models)" { return "All models" }
        if label.hasPrefix("Current week ("), label.hasSuffix(")") {
            return String(label.dropFirst("Current week (".count).dropLast())
        }
        return label
    }

    /// Turns `Jul 31 at 2pm (Asia/Bangkok)` into an instant.
    ///
    /// The year is missing from the CLI's wording, so it is taken as the one
    /// that puts the date ahead of now — without that, every reset in January
    /// would read as eleven months past. Both `2pm` and `1:59pm` occur.
    /// Returns nil rather than guessing if anything fails to parse; the caller
    /// falls back to showing the CLI's own words.
    static func resetDate(from text: String, now: Date) -> Date? {
        let zoneName = text.slice(between: "(", and: ")")
        let withoutZone = text
            .replacingOccurrences(of: "(\(zoneName ?? ""))", with: "")
            .trimmingCharacters(in: .whitespaces)

        let zone = zoneName.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        for format in ["MMM d 'at' h:mma", "MMM d 'at' ha"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: withoutZone) else { continue }

            var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
            for year in [calendar.component(.year, from: now), calendar.component(.year, from: now) + 1] {
                parts.year = year
                guard let candidate = calendar.date(from: parts) else { continue }
                // A reset slightly in the past is normal — the reading is a
                // couple of minutes old. Months back means the year was wrong.
                if candidate > now.addingTimeInterval(-86_400) { return candidate }
            }
        }
        return nil
    }
}

/// Reads the subscription tier out of `claude auth status`, which answers JSON.
///
/// Only the tier is taken. That command also reports the account's email and
/// organisation id, and this app has no reason to hold either.
public enum PlanIdentityParser {
    public static func planName(fromAuthStatus json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["subscriptionType"] as? String,
              !type.isEmpty
        else { return nil }
        return type.prefix(1).uppercased() + type.dropFirst()
    }
}

private extension String {
    func slice(between open: Character, and close: Character) -> String? {
        guard let start = firstIndex(of: open), let end = lastIndex(of: close), start < end else {
            return nil
        }
        return String(self[index(after: start)..<end])
    }
}
