import XCTest
@testable import AssistantState

/// Telling a sub-agent that is working from one that has stopped answering.
///
/// The complaint behind it: while a sub-agent ran, the character showed the same
/// thing whether it was mid-step or the session had died.
final class SubagentLivenessTests: XCTestCase {
    /// Fixed, so every case below is a date arithmetic problem with one answer
    /// and none of them depend on when the suite runs.
    private let spoke = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        spoke.addingTimeInterval(seconds)
    }

    func testJustSpokeIsRunning() {
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(0)), .running)
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(29)), .running)
    }

    /// The boundary is inclusive on the quiet side, and stated here so a later
    /// change to the constant has to change this line too.
    func testAtTheThresholdItIsQuietAndSaysForHowLong() {
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(30)), .quiet(30))
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(90)), .quiet(90))
    }

    func testLongEnoughIsPresumedLost() {
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(5 * 60)), .presumedLost)
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(60 * 60)), .presumedLost)
    }

    /// A clock that jumped backwards must not produce a negative quiet time,
    /// which would render as "quiet for -4 seconds". Alive is the only honest
    /// reading of an event stamped in the future.
    func testAnEventFromTheFutureReadsAsRunning() {
        XCTAssertEqual(subagentLiveness(lastEventAt: spoke, now: at(-5)), .running)
    }

    /// Same arguments, same answer — the check that it is a function of its
    /// inputs and not of the wall clock.
    func testItIsDeterministic() {
        XCTAssertEqual(
            subagentLiveness(lastEventAt: spoke, now: at(45)),
            subagentLiveness(lastEventAt: spoke, now: at(45))
        )
    }
}
