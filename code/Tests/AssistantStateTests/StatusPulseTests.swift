import XCTest
@testable import AssistantState

final class StatusPulseTests: XCTestCase {
    func testBusyStatesBreathe() {
        for state in [AssistantState.thinking, .working] {
            XCTAssertEqual(statusPulse(for: state), .busy, "\(state) should breathe")
            XCTAssertTrue(statusPulse(for: state).isAnimated)
        }
    }

    /// The half that actually matters on screen: a character still moving after
    /// the answer arrived reads as work still running. This is the bug the
    /// first version shipped with, so it is the test written first.
    func testEverythingElseIsStill() {
        for state in [AssistantState.idle, .listening, .success, .error] {
            XCTAssertEqual(statusPulse(for: state), .still, "\(state) should be still")
            XCTAssertFalse(statusPulse(for: state).isAnimated)
        }
    }

    /// The size step the owner asked for, pinned exactly rather than as a range:
    /// 10% is the requirement, and a later nudge to 30% should have to be typed
    /// here too.
    func testTheBreathIsTenPercent() {
        XCTAssertEqual(StatusPulse.busy.peakScale, 1.1, accuracy: 0.0001)
        XCTAssertEqual(pulseScale(.busy, at: 0.6), 1.1, accuracy: 0.0001)
    }

    /// Still means still at *every* moment, not merely at the start — the
    /// property the `@State`-and-`repeatForever` version could not hold.
    func testAStillPulseNeverMoves() {
        for t in stride(from: 0.0, through: 5.0, by: 0.05) {
            XCTAssertEqual(pulseProgress(.still, at: t), 0, accuracy: 0.0001)
            XCTAssertEqual(pulseScale(.still, at: t), 1, accuracy: 0.0001)
        }
    }

    /// Rest, full expansion, rest — one period, both ends closed.
    func testTheBreathGoesOutAndBack() {
        XCTAssertEqual(pulseProgress(.busy, at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(pulseProgress(.busy, at: 0.6), 1, accuracy: 0.0001)
        XCTAssertEqual(pulseProgress(.busy, at: 1.2), 0, accuracy: 0.0001)
    }

    /// It never leaves the range the colours and the scale are mixed over, so
    /// no frame can overshoot into a colour or a size nobody chose.
    func testProgressStaysBetweenRestAndPeak() {
        for t in stride(from: 0.0, through: 10.0, by: 0.017) {
            let p = pulseProgress(.busy, at: t)
            XCTAssertGreaterThanOrEqual(p, 0)
            XCTAssertLessThanOrEqual(p, 1)
        }
    }

    /// The halo and the badge each read the clock for themselves. They stay in
    /// step only because this is a function of the time and nothing else —
    /// same moment, same answer, no shared mutable phase to drift apart.
    func testTheSameMomentAlwaysGivesTheSamePhase() {
        for t in stride(from: 0.0, through: 3.0, by: 0.13) {
            XCTAssertEqual(pulseProgress(.busy, at: t), pulseProgress(.busy, at: t), accuracy: 0)
            XCTAssertEqual(
                pulseProgress(.busy, at: t),
                pulseProgress(.busy, at: t + StatusPulse.busy.period),
                accuracy: 0.0001,
                "one period later is the same point in the breath"
            )
        }
    }

    func testAPulseNeedsBothMovementAndTime() {
        XCTAssertFalse(StatusPulse(peakScale: 1.1, period: 0).isAnimated)
        XCTAssertFalse(StatusPulse(peakScale: 1, period: 1.2).isAnimated)
    }
}
