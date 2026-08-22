import FunctionalCore
import Foundation

public enum LoopCommandError: Error, Equatable, Sendable {
    case unreadableInterval(String)
    case intervalTooShort(seconds: TimeInterval, minimum: TimeInterval)
    case intervalTooLong(seconds: TimeInterval, maximum: TimeInterval)
}

public struct LoopSchedule: Equatable, Sendable {
    public let interval: TimeInterval
    public let note: String
    public let startedAt: Date
    public let nextFireAt: Date
    public let firedCount: Int

    public static let minimumInterval: TimeInterval = 60
    public static let maximumInterval: TimeInterval = 2 * 60 * 60
    public static let maximumDuration: TimeInterval = 12 * 60 * 60

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

    public func fired(at now: Date) -> LoopSchedule {
        LoopSchedule(
            interval: interval,
            note: note,
            startedAt: startedAt,
            nextFireAt: now.addingTimeInterval(interval),
            firedCount: firedCount + 1
        )
    }

    public func postponed(to next: Date) -> LoopSchedule {
        LoopSchedule(
            interval: interval,
            note: note,
            startedAt: startedAt,
            nextFireAt: next,
            firedCount: firedCount
        )
    }

    public var intervalDescription: String {
        let minutes = Int((interval / 60).rounded())
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

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

public enum LoopCommand {
    public enum Request: Equatable, Sendable {
        case status
        case stop
        case start(interval: TimeInterval, note: String)
    }

    static let stopWords = ["stop", "off", "cancel", "end", "หยุด", "เลิก", "พอ"]

    public static func parse(_ argument: String) -> Either<LoopCommandError, Request> {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .right(.status) }
        if stopWords.contains(trimmed.lowercased()) { return .right(.stop) }

        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let head = parts[0]
        var note = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

        var duration = head
        if unit(of: head) == nil, let separate = note.split(separator: " ").first,
           let spelled = spelledUnit(String(separate)) {
            duration += spelled
            note = note.dropFirst(separate.count).trimmingCharacters(in: .whitespaces)
        }

        let carried = note
        return parseInterval(duration).map { Request.start(interval: $0, note: carried) }^
    }

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
        let aBareNumberMeansMinutes: TimeInterval = 60
        return .right(number * (unitFound?.multiplier ?? aBareNumberMeansMinutes))
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

    private static func unit(of text: String) -> Unit? {
        units
            .filter { text.count > $0.suffix.count && text.hasSuffix($0.suffix) }
            .max { $0.suffix.count < $1.suffix.count }
    }

    private static func spelledUnit(_ word: String) -> String? {
        let lowered = word.lowercased()
        return units.first { $0.suffix == lowered }?.suffix
    }
}
