import XCTest
@testable import SecretaryCore

/// The time shown beside a message's name.
final class MessageTimeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
    private let locale = Locale(identifier: "en_US_POSIX")

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func label(_ when: String, now: String) -> String {
        MessageTime.label(
            for: date(when),
            now: date(now),
            calendar: calendar,
            locale: locale
        )
    }

    /// Today: the time on its own. A date on every line of a conversation you
    /// are having right now is noise.
    func testTodayShowsTheTimeOnly() {
        let shown = label("2026-08-02 14:32", now: "2026-08-02 18:00")
        XCTAssertTrue(shown.contains("2:32") || shown.contains("14:32"), shown)
        XCTAssertFalse(shown.contains("2026"), shown)
        XCTAssertFalse(shown.contains("8/2"), shown)
    }

    /// Yesterday, or last week: the date comes with it. A bare time on an old
    /// message reads as one sent minutes ago.
    func testAnotherDayShowsTheDateToo() {
        let shown = label("2026-07-30 09:05", now: "2026-08-02 18:00")
        XCTAssertTrue(shown.contains("7/30"), shown)
    }

    /// Just before midnight and just after are different days, even minutes
    /// apart — the rule is the calendar day, not elapsed time.
    func testJustBeforeMidnightIsAnotherDay() {
        let shown = label("2026-08-01 23:58", now: "2026-08-02 00:04")
        XCTAssertTrue(shown.contains("8/1"), shown)
    }

    func testTheSameInstantIsToday() {
        let shown = label("2026-08-02 00:00", now: "2026-08-02 00:00")
        XCTAssertFalse(shown.contains("8/2"), shown)
    }
}
