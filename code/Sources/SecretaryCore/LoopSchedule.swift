import FunctionalCore
import Foundation

/// Why a `/loop` request was refused.
public enum LoopCommandError: Error, Equatable, Sendable {
    /// The interval wasn't a duration anyone wrote on purpose.
    case unreadableInterval(String)
    /// Faster than this and a check would arrive before the previous answer
    /// finished — and it would spend the user's Claude subscription doing it.
    case intervalTooShort(seconds: TimeInterval, minimum: TimeInterval)
    case intervalTooLong(seconds: TimeInterval, maximum: TimeInterval)
}

/// A standing instruction to check back in every so often.
///
/// The Secretary can already answer "where are we in the agenda?" when asked.
/// What it could not do is ask itself, which is the whole of what a person
/// running a workshop wants: they are in front of a room and cannot type. This
/// is that timer, kept as a value so the arithmetic of *when* is testable
/// without waiting for real minutes to pass.
///
/// Deliberately session-only. A loop is tied to something happening right now,
/// and one that survived a restart would wake up hours later asking about an
/// agenda that finished — the same reason write and browser grants are never
/// persisted.
public struct LoopSchedule: Equatable, Sendable {
    /// How long between checks.
    public let interval: TimeInterval
    /// What to report each time, in the user's own words.
    public let note: String
    public let startedAt: Date
    /// When the next check is due. Moved forward on each fire rather than
    /// derived from `startedAt`, so a check that had to be skipped doesn't
    /// leave the loop trying to catch up on missed ones.
    public let nextFireAt: Date
    public let firedCount: Int

    /// A minute is the floor: a reply takes tens of seconds, and anything
    /// tighter would have checks queuing behind each other.
    public static let minimumInterval: TimeInterval = 60
    /// Past a couple of hours this is a reminder, not a loop, and the user is
    /// better served by asking when they want to know.
    public static let maximumInterval: TimeInterval = 2 * 60 * 60
    /// A working day. A loop nobody stopped must not still be running
    /// tomorrow morning, quietly spending tokens.
    public static let maximumDuration: TimeInterval = 12 * 60 * 60

    /// What to report when the user didn't say. Phrased as an agenda check
    /// because that is what asked for the feature, but it reads sensibly for
    /// anything being watched.
    public static let defaultNote =
        "บอกสั้นๆ ว่าตอนนี้ถึงหัวข้อไหนตามที่คุยกันไว้ และถัดไปคืออะไร"

    public init(
        interval: TimeInterval,
        note: String,
        startedAt: Date,
        nextFireAt: Date,
        firedCount: Int = 0
    ) {
        self.interval = interval
        self.note = note
        self.startedAt = startedAt
        self.nextFireAt = nextFireAt
        self.firedCount = firedCount
    }

    /// A fresh loop's first check is one interval away, not immediate: the user
    /// has just been talking to the Secretary, so it already knows where things
    /// stand.
    public static func starting(
        interval: TimeInterval,
        note: String,
        now: Date
    ) -> LoopSchedule {
        LoopSchedule(
            interval: interval,
            note: note.isEmpty ? defaultNote : note,
            startedAt: now,
            nextFireAt: now.addingTimeInterval(interval)
        )
    }

    public func isDue(at now: Date) -> Bool { now >= nextFireAt }

    public func hasRunTooLong(at now: Date) -> Bool {
        now.timeIntervalSince(startedAt) >= Self.maximumDuration
    }

    /// The loop after a check has gone out. The next one is measured from now,
    /// so a check delayed by a reply still leaves a full interval of quiet.
    public func fired(at now: Date) -> LoopSchedule {
        LoopSchedule(
            interval: interval,
            note: note,
            startedAt: startedAt,
            nextFireAt: now.addingTimeInterval(interval),
            firedCount: firedCount + 1
        )
    }

    /// A check delayed because the Secretary was mid-reply. The due time moves
    /// on so the loop doesn't spin, and nothing is counted as delivered.
    public func postponed(to next: Date) -> LoopSchedule {
        LoopSchedule(
            interval: interval,
            note: note,
            startedAt: startedAt,
            nextFireAt: next,
            firedCount: firedCount
        )
    }

    /// "every 10 minutes" in the shortest form that still reads.
    public var intervalDescription: String {
        let minutes = Int((interval / 60).rounded())
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// The prompt a check sends. Says the time in words, because the model has
    /// no clock of its own and this is a question about now.
    public func checkPrompt(at now: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let clock = String(format: "%02d:%02d", hour, minute)
        return """
        ⏱ Loop check — เวลาจริงตอนนี้คือ \(clock) (ตั้งไว้ทุก \(intervalDescription))

        \(note)

        ตอบสั้นๆ ถ้าไม่มีอะไรเปลี่ยนจากรอบก่อน บอกบรรทัดเดียวว่ายังอยู่ที่เดิม \
        และอย่าถามกลับ เพราะรอบนี้ไม่มีใครพิมพ์อะไรมา
        """
    }
}

/// Reading the argument of `/loop`.
///
/// Kept apart from the schedule itself so the parsing has no clock in it: the
/// command says *how often*, and only the Secretary knows *when* it was said.
public enum LoopCommand {
    /// What the user asked `/loop` to do.
    public enum Request: Equatable, Sendable {
        /// Report the loop's state, or how to start one.
        case status
        case stop
        case start(interval: TimeInterval, note: String)
    }

    static let stopWords = ["stop", "off", "cancel", "end", "หยุด", "เลิก", "พอ"]

    /// Parses everything after `/loop`.
    ///
    /// Forgiving about how the duration is written — `10m`, `10`, `10 min`,
    /// `10 นาที`, `1h`, `90s` all work — because this gets typed one-handed
    /// while something else is going on.
    public static func parse(_ argument: String) -> Either<LoopCommandError, Request> {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .right(.status) }
        if stopWords.contains(trimmed.lowercased()) { return .right(.stop) }

        // The duration is the first word; whatever follows is what to report.
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let head = parts[0]
        var note = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

        // "10 นาที ..." and "10 min ..." put the unit in its own word, so it has
        // to be taken off the note rather than read as part of the report.
        var duration = head
        if unit(of: head) == nil, let separate = note.split(separator: " ").first,
           let spelled = spelledUnit(String(separate)) {
            duration += spelled
            note = note.dropFirst(separate.count).trimmingCharacters(in: .whitespaces)
        }

        let carried = note
        return parseInterval(duration).map { Request.start(interval: $0, note: carried) }^
    }

    /// A duration on its own, checked against the limits. Shared with the
    /// model-facing block so a loop the assistant starts can't be faster or
    /// longer-lived than one the user could have typed.
    public static func parseInterval(_ text: String) -> Either<LoopCommandError, TimeInterval> {
        seconds(of: text).flatMap { value -> Either<LoopCommandError, TimeInterval> in
            if value < LoopSchedule.minimumInterval {
                return .left(.intervalTooShort(seconds: value, minimum: LoopSchedule.minimumInterval))
            }
            if value > LoopSchedule.maximumInterval {
                return .left(.intervalTooLong(seconds: value, maximum: LoopSchedule.maximumInterval))
            }
            return .right(value)
        }^
    }

    private static func seconds(of text: String) -> Either<LoopCommandError, TimeInterval> {
        let lowered = text.lowercased()
        let unitFound = unit(of: lowered)
        let numberPart = unitFound.map { String(lowered.dropLast($0.suffix.count)) } ?? lowered
        guard let number = Double(numberPart.trimmingCharacters(in: .whitespaces)), number > 0 else {
            return .left(.unreadableInterval(text))
        }
        // A bare number is minutes: "/loop 10" means ten minutes, not ten
        // seconds, and certainly not ten hours.
        return .right(number * (unitFound?.multiplier ?? 60))
    }

    private struct Unit { let suffix: String; let multiplier: TimeInterval }

    private static let units = [
        Unit(suffix: "seconds", multiplier: 1), Unit(suffix: "second", multiplier: 1),
        Unit(suffix: "secs", multiplier: 1), Unit(suffix: "sec", multiplier: 1),
        Unit(suffix: "s", multiplier: 1),
        Unit(suffix: "minutes", multiplier: 60), Unit(suffix: "minute", multiplier: 60),
        Unit(suffix: "mins", multiplier: 60), Unit(suffix: "min", multiplier: 60),
        Unit(suffix: "นาที", multiplier: 60), Unit(suffix: "m", multiplier: 60),
        Unit(suffix: "hours", multiplier: 3600), Unit(suffix: "hour", multiplier: 3600),
        Unit(suffix: "hrs", multiplier: 3600), Unit(suffix: "hr", multiplier: 3600),
        Unit(suffix: "ชั่วโมง", multiplier: 3600), Unit(suffix: "ชม", multiplier: 3600),
        Unit(suffix: "h", multiplier: 3600)
    ]

    /// The *longest* matching suffix wins, not the first one listed. Order
    /// alone got this wrong: `10minutes` ends in `s`, so a first-match search
    /// read it as ten seconds and then choked on the leftover `10minute`.
    private static func unit(of text: String) -> Unit? {
        units
            .filter { text.count > $0.suffix.count && text.hasSuffix($0.suffix) }
            .max { $0.suffix.count < $1.suffix.count }
    }

    /// A unit written as its own word, as in "10 นาที" or "10 m".
    private static func spelledUnit(_ word: String) -> String? {
        let lowered = word.lowercased()
        return units.first { $0.suffix == lowered }?.suffix
    }
}
