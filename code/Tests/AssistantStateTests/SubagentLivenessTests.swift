import XCTest
@testable import AssistantState

final class SubagentLivenessTests: XCTestCase {
    private let spoke = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        spoke.addingTimeInterval(seconds)
    }

    func testJustSpokeIsRunning() {
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(0)), .running)
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(29)), .running)
    }

    func testTheQuietThresholdIsInclusiveAndTheSilenceIsReportedWithIt() {
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(30)), .quiet(30))
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(90)), .quiet(90))
    }

    func testLongEnoughIsPresumedLostRatherThanStillQuiet() {
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(5 * 60)), .presumedLost)
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(60 * 60)), .presumedLost)
    }

    func testAnEventFromTheFutureReadsAsRunningRatherThanANegativeQuietTime() {
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(-5)), .running)
    }

    func testTheSameArgumentsGiveTheSameAnswerRatherThanReadingTheWallClock() {
        XCTAssertEqual(
            subagentLiveness(lastEventAt: spoke, now: at(45)),
            subagentLiveness(lastEventAt: spoke, now: at(45))
        )
    }
}
