import XCTest
@testable import SecretaryCore

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

    func testTodayShowsTheTimeOnly() {
        let shown = label("2026-08-02 14:32", now: "2026-08-02 18:00")
        XCTAssertTrue(shown.contains("2:32") || shown.contains("14:32"), shown)
        XCTAssertFalse(shown.contains("2026"), shown)
        XCTAssertFalse(shown.contains("8/2"), shown)
    }

    func testAnotherDayShowsTheDateToo() {
        let shown = label("2026-07-30 09:05", now: "2026-08-02 18:00")
        XCTAssertTrue(shown.contains("7/30"), shown)
    }

    func testJustBeforeMidnightIsAnotherDay() {
        let shown = label("2026-08-01 23:58", now: "2026-08-02 00:04")
        XCTAssertTrue(shown.contains("8/1"), shown)
    }

    func testTheSameInstantIsToday() {
        let shown = label("2026-08-02 00:00", now: "2026-08-02 00:00")
        XCTAssertFalse(shown.contains("8/2"), shown)
    }
}
