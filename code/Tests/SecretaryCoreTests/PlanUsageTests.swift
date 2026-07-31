import XCTest
@testable import SecretaryCore

/// Reading the plan limits out of `claude -p -- /usage`.
///
/// It is text meant for a terminal, owned by another program, so the parser is
/// held to one rule above all: recognise it or say nothing. A percentage that is
/// wrong — or right but stale — is worse than a blank, because this is the
/// number people use to decide whether to keep working.
final class PlanUsageTests: XCTestCase {
    /// Captured verbatim from a real run.
    private let real = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 25% used · resets Jul 31 at 1:59pm (Asia/Bangkok)
    Current week (all models): 3% used · resets Aug 7 at 8:59am (Asia/Bangkok)
    Current week (Fable): 0% used

    What's contributing to your limits usage?
    Approximate, based on local sessions on this machine — does not include other devices.

    Last 24h · 510 requests · 11 sessions
      83% of your usage was at >150k context
    """

    func testItReadsEveryLimitLine() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse(real))
        XCTAssertEqual(usage.limits.count, 3)
        XCTAssertEqual(usage.limits[0].label, "Session")
        XCTAssertEqual(usage.limits[0].fraction, 0.25)
        XCTAssertEqual(usage.limits[0].resets, "Jul 31 at 1:59pm (Asia/Bangkok)")
        XCTAssertEqual(usage.limits[1].label, "This week")
        XCTAssertEqual(usage.limits[1].fraction, 0.03)
        XCTAssertEqual(usage.limits[2].label, "This week (Fable)")
        XCTAssertEqual(usage.limits[2].fraction, 0)
        XCTAssertNil(usage.limits[2].resets, "That line carries no reset time")
    }

    /// The prose around the numbers is not a limit and must not become a row —
    /// especially the "83% of your usage was at >150k context" line, which is a
    /// percentage of something else entirely.
    func testProseIsNotMistakenForALimit() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse(real))
        XCTAssertFalse(
            usage.limits.contains { $0.label.contains("context") || $0.fraction == 0.83 },
            "Got: \(usage.limits.map(\.label))"
        )
    }

    /// If Claude Code rewords this, the answer is nothing rather than a guess.
    func testUnrecognisedOutputYieldsNothing() {
        XCTAssertNil(PlanUsageParser.parse(""))
        XCTAssertNil(PlanUsageParser.parse("Not logged in."))
        XCTAssertNil(PlanUsageParser.parse("Session usage is at three quarters."))
    }

    /// An account over its allowance reports more than 100; a bar drawn past its
    /// own end reads as a rendering bug rather than as bad news.
    func testOverHundredIsClamped() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse("Current session: 140% used"))
        XCTAssertEqual(usage.limits[0].fraction, 1)
        XCTAssertEqual(usage.limits[0].percentText, "100% used")
    }

    func testPercentTextRounds() {
        XCTAssertEqual(
            PlanUsage.Limit(label: "x", fraction: 0.256, resets: nil).percentText,
            "26% used"
        )
    }
}
