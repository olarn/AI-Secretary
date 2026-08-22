import XCTest
@testable import AssistantState

final class StatusPulseTests: XCTestCase {
    func testBusyStatesBreathe() {
        for state in [AssistantState.thinking, .working] {
            XCTAssertEqual(statusPulse(for: state), .busy, "\(state) should breathe")
            XCTAssertTrue(statusPulse(for: state).isAnimated)
        }
    }

    func testAStateThatIsNotBusyIsStillBecauseMovementAfterTheAnswerReadsAsWorkStillRunning() {
        for state in [AssistantState.idle, .listening, .success, .error] {
            XCTAssertEqual(statusPulse(for: state), .still, "\(state) should be still")
            XCTAssertFalse(statusPulse(for: state).isAnimated)
        }
    }

    func testTheBreathIsExactlyTenPercentSoALaterNudgeHasToBeTypedHereToo() {
        XCTAssertEqual(StatusPulse.busy.peakScale, 1.1, accuracy: 0.0001)
        XCTAssertEqual(pulseScale(.busy, at: 0.6), 1.1, accuracy: 0.0001)
    }

    func testAStillPulseIsZeroAtEveryMomentNotMerelyAtTheStart() {
        for t in stride(from: 0.0, through: 5.0, by: 0.05) {
            XCTAssertEqual(pulseProgress(.still, at: t), 0, accuracy: 0.0001)
            XCTAssertEqual(pulseScale(.still, at: t), 1, accuracy: 0.0001)
        }
    }

    func testTheBreathGoesOutAndBackWithinOnePeriod() {
        XCTAssertEqual(pulseProgress(.busy, at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(pulseProgress(.busy, at: 0.6), 1, accuracy: 0.0001)
        XCTAssertEqual(pulseProgress(.busy, at: 1.2), 0, accuracy: 0.0001)
    }

    func testProgressNeverOvershootsTheRangeTheColourAndScaleAreMixedOver() {
        for t in stride(from: 0.0, through: 10.0, by: 0.017) {
            let p = pulseProgress(.busy, at: t)
            XCTAssertGreaterThanOrEqual(p, 0)
            XCTAssertLessThanOrEqual(p, 1)
        }
    }

    func testTheHaloAndBadgeStayInStepBecauseThePhaseIsAFunctionOfTheMomentAlone() {
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
