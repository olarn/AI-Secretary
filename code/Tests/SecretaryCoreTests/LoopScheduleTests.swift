import XCTest
@testable import SecretaryCore

/// Reading `/loop`'s argument, and the arithmetic of when the next check is
/// due. Both are pure, so neither test has to wait for a real minute.
final class LoopScheduleTests: XCTestCase {
    private func start(_ argument: String) -> LoopCommand.Request? {
        LoopCommand.parse(argument).toOption().toOptional()
    }

    // MARK: - What the user typed

    func testABareNumberMeansMinutes() {
        XCTAssertEqual(start("10"), .start(interval: 600, note: ""))
    }

    /// All the ways someone types ten minutes one-handed while a room waits.
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

    /// Whatever follows the duration is what to report — and a unit spelled as
    /// its own word must not end up in it.
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

    // MARK: - What must be refused

    /// A check every ten seconds would arrive before the previous answer had
    /// finished, and would spend the user's subscription doing it.
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

    // MARK: - When the next check is due

    /// The first check waits a full interval: the user has just been talking to
    /// the Secretary, so an immediate one would only repeat what was said.
    func testAFreshLoopIsNotDueImmediately() {
        let now = Date()
        let loop = LoopSchedule.starting(interval: 600, note: "", now: now)
        XCTAssertFalse(loop.isDue(at: now))
        XCTAssertFalse(loop.isDue(at: now.addingTimeInterval(599)))
        XCTAssertTrue(loop.isDue(at: now.addingTimeInterval(600)))
        XCTAssertEqual(loop.firedCount, 0)
    }

    /// Measured from the check that actually went out, not from the start — a
    /// check delayed by a long reply must still leave a full interval of quiet
    /// rather than firing again at once to catch up.
    func testTheNextCheckIsMeasuredFromTheLastOne() {
        let now = Date()
        let loop = LoopSchedule.starting(interval: 600, note: "", now: now)
        let late = now.addingTimeInterval(700)
        let fired = loop.fired(at: late)
        XCTAssertEqual(fired.firedCount, 1)
        XCTAssertFalse(fired.isDue(at: late.addingTimeInterval(599)))
        XCTAssertTrue(fired.isDue(at: late.addingTimeInterval(600)))
    }

    /// Postponing moves the due time without counting a delivery.
    func testPostponingDoesNotCountAsACheck() {
        let now = Date()
        let loop = LoopSchedule.starting(interval: 600, note: "", now: now)
            .postponed(to: now.addingTimeInterval(630))
        XCTAssertEqual(loop.firedCount, 0)
        XCTAssertFalse(loop.isDue(at: now.addingTimeInterval(620)))
    }

    /// A loop nobody stopped must not still be running tomorrow, quietly
    /// spending tokens.
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

    // MARK: - What the check asks

    /// The model has no clock, so the check has to say what time it is — that
    /// is the entire point of the feature.
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
