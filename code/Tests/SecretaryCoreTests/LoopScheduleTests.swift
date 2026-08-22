import XCTest
@testable import SecretaryCore

final class LoopScheduleTests: XCTestCase {
    private func start(_ argument: String) -> LoopCommand.Request? {
        LoopCommand.parse(argument).toOption().toOptional()
    }

    func testABareNumberMeansMinutes() {
        XCTAssertEqual(start("10"), .start(interval: 600, note: ""))
    }

    func testTheUsualWaysOfWritingTenMinutes() {
        for argument in ["10m", "10 m", "10min", "10 min", "10 minutes", "10 นาที"] {
            XCTAssertEqual(
                start(argument), .start(interval: 600, note: ""),
                "Failed on “\(argument)”"
            )
        }
    }

    func testHoursAndSecondsAreUnderstood() {
        XCTAssertEqual(start("1h"), .start(interval: 3600, note: ""))
        XCTAssertEqual(start("90s"), .start(interval: 90, note: ""))
    }

    func testTheRestOfTheLineIsWhatToReport() {
        XCTAssertEqual(
            start("10m บอกว่าถึงหัวข้อไหนแล้ว"),
            .start(interval: 600, note: "บอกว่าถึงหัวข้อไหนแล้ว")
        )
        XCTAssertEqual(
            start("10 นาที บอกว่าถึงหัวข้อไหนแล้ว"),
            .start(interval: 600, note: "บอกว่าถึงหัวข้อไหนแล้ว")
        )
    }

    func testNoArgumentAsksForTheState() {
        XCTAssertEqual(start(""), .status)
        XCTAssertEqual(start("   "), .status)
    }

    func testStopIsUnderstoodInBothLanguages() {
        for word in ["stop", "off", "STOP", "หยุด", "พอ"] {
            XCTAssertEqual(start(word), .stop, "Failed on “\(word)”")
        }
    }

    func testTooFastIsRefusedWithTheLimit() {
        XCTAssertEqual(
            LoopCommand.parse("10s").swap().toOption().toOptional(),
            .intervalTooShort(seconds: 10, minimum: 60)
        )
    }

    func testTooSlowIsRefused() {
        XCTAssertEqual(
            LoopCommand.parse("5h").swap().toOption().toOptional(),
            .intervalTooLong(seconds: 5 * 3600, maximum: 2 * 3600)
        )
    }

    func testSomethingThatIsNotADurationIsRefused() {
        for argument in ["soon", "-5m", "0m", "m"] {
            XCTAssertTrue(
                LoopCommand.parse(argument).isLeft,
                "“\(argument)” should not have parsed as a duration"
            )
        }
    }

    func testAFreshLoopIsNotDueImmediately() {
        let now = Date()
        let loop = LoopSchedule.starting(interval: 600, note: "", now: now)
        XCTAssertFalse(loop.isDue(at: now))
        XCTAssertFalse(loop.isDue(at: now.addingTimeInterval(599)))
        XCTAssertTrue(loop.isDue(at: now.addingTimeInterval(600)))
        XCTAssertEqual(loop.firedCount, 0)
    }

    func testTheNextCheckIsMeasuredFromTheLastOne() {
        let now = Date()
        let loop = LoopSchedule.starting(interval: 600, note: "", now: now)
        let late = now.addingTimeInterval(700)
        let fired = loop.fired(at: late)
        XCTAssertEqual(fired.firedCount, 1)
        XCTAssertFalse(fired.isDue(at: late.addingTimeInterval(599)))
        XCTAssertTrue(fired.isDue(at: late.addingTimeInterval(600)))
    }

    func testPostponingDoesNotCountAsACheck() {
        let now = Date()
        let loop = LoopSchedule.starting(interval: 600, note: "", now: now)
            .postponed(to: now.addingTimeInterval(630))
        XCTAssertEqual(loop.firedCount, 0)
        XCTAssertFalse(loop.isDue(at: now.addingTimeInterval(620)))
    }

    func testALoopGivesUpAfterAWorkingDay() {
        let now = Date()
        let loop = LoopSchedule.starting(interval: 600, note: "", now: now)
        XCTAssertFalse(loop.hasRunTooLong(at: now.addingTimeInterval(11 * 3600)))
        XCTAssertTrue(loop.hasRunTooLong(at: now.addingTimeInterval(12 * 3600)))
    }

    func testAnEmptyNoteFallsBackToTheAgendaQuestion() {
        let loop = LoopSchedule.starting(interval: 600, note: "", now: Date())
        XCTAssertEqual(loop.note, LoopSchedule.defaultNote)
    }

    func testTheCheckStatesTheRealTime() {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 30
        components.hour = 10; components.minute = 46
        let when = Calendar.current.date(from: components)!
        let prompt = LoopSchedule
            .starting(interval: 600, note: "ถึงหัวข้อไหนแล้ว", now: when)
            .checkPrompt(at: when)
        XCTAssertTrue(prompt.contains("10:46"), "Got: \(prompt)")
        XCTAssertTrue(prompt.contains("ถึงหัวข้อไหนแล้ว"))
        XCTAssertTrue(prompt.contains("10m"))
    }

    func testTheIntervalReadsAsPeopleWriteIt() {
        func described(_ seconds: TimeInterval) -> String {
            LoopSchedule.starting(interval: seconds, note: "", now: Date()).intervalDescription
        }
        XCTAssertEqual(described(600), "10m")
        XCTAssertEqual(described(3600), "1h")
        XCTAssertEqual(described(5400), "1h 30m")
    }
}
