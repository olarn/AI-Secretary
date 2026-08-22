import Foundation

public struct PlanUsage: Equatable, Sendable {
    public enum Scope: Equatable, Sendable {
        case session
        case week
    }

    public struct Limit: Equatable, Sendable {
        public let scope: Scope
        public let name: String
        public let fraction: Double
        public let resetsText: String?
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

        public func resetDescription(now: Date = Date()) -> String? {
            guard let resetsAt, resetsAt > now,
                  resetsAt.timeIntervalSince(now) < 86_400
            else { return resetsText.map { "Resets \($0)" } }
            return "Resets in \(UsageFormat.duration(until: resetsAt, from: now))"
        }
    }

    public struct Activity: Equatable, Sendable {
        public let period: String
        public let requests: Int
        public let sessions: Int
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

    public static let activityNote =
        "Counted from sessions on this Mac only — other devices and claude.ai aren't included."

    public var session: [Limit] { limits.filter { $0.scope == .session } }
    public var weekly: [Limit] { limits.filter { $0.scope == .week } }
}

public enum PlanUsageParser {
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

    private static let periodLine = try? NSRegularExpression(
        pattern: #"^(Last [^·]+)·\s*([\d,]+)\s+requests\s*·\s*([\d,]+)\s+sessions\s*$"#
    )

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

    static func displayName(for label: String) -> String {
        if label == "Current week (all models)" { return "All models" }
        if label.hasPrefix("Current week ("), label.hasSuffix(")") {
            return String(label.dropFirst("Current week (".count).dropLast())
        }
        return label
    }

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
                if candidate > now.addingTimeInterval(-86_400) { return candidate }
            }
        }
        return nil
    }
}

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
