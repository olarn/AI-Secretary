import XCTest
@testable import AssistantState

final class StatusPulseTests: XCTestCase {
    func testBusyStatesBreathe() {
        for state in [AssistantState.thinking, .working] {
            XCTAssertEqual(statusPulse(for: state), .busy, "\(state) should breathe")
            XCTAssertTrue(statusPulse(for: state).isAnimated)
        }
    }

    /// The half that actually matters on screen: a badge still moving after the
    /// answer arrived reads as work still running.
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
    }

    /// Dark and light are one animation with the size change, so they share the
    /// period — that is the whole of "ตรงกับจังหวะ pulse".
    func testColourAndSizeShareOneClock() {
        let pulse = StatusPulse.busy
        XCTAssertLessThan(pulse.dimOpacity, 1, "the fill has to actually fade")
        XCTAssertGreaterThan(pulse.period, 0)
        XCTAssertEqual(pulse.halfCycle, pulse.period / 2, accuracy: 0.0001)
    }

    func testStillMeansNothingToAnimate() {
        XCTAssertFalse(StatusPulse.still.isAnimated)
        XCTAssertEqual(StatusPulse.still.peakScale, 1, accuracy: 0.0001)
        XCTAssertEqual(StatusPulse.still.dimOpacity, 1, accuracy: 0.0001)
    }

    /// A pulse with movement but no time to move in is still, and so is one with
    /// time but nowhere to go. Either handed to `repeatForever` would run for
    /// ever and show nothing.
    func testAPulseNeedsBothMovementAndTime() {
        XCTAssertFalse(StatusPulse(peakScale: 1.1, dimOpacity: 0.5, period: 0).isAnimated)
        XCTAssertFalse(StatusPulse(peakScale: 1, dimOpacity: 1, period: 1.2).isAnimated)
    }
}
