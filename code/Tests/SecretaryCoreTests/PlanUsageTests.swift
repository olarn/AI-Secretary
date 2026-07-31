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
        XCTAssertEqual(usage.limits[0].name, "Current session")
        XCTAssertEqual(usage.limits[0].fraction, 0.25)
        XCTAssertEqual(usage.limits[0].resetsText, "Jul 31 at 1:59pm (Asia/Bangkok)")
        XCTAssertEqual(usage.limits[1].name, "All models")
        XCTAssertEqual(usage.limits[1].fraction, 0.03)
        XCTAssertEqual(usage.limits[2].name, "Fable")
        XCTAssertEqual(usage.limits[2].fraction, 0)
        XCTAssertNil(usage.limits[2].resetsText, "That line carries no reset time")
    }

    /// The Claude app groups these; the CLI does not, so the split has to be
    /// derived from the wording and is worth pinning.
    func testTheSessionAndWeeklyWindowsAreSeparated() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse(real))
        XCTAssertEqual(usage.session.map(\.name), ["Current session"])
        XCTAssertEqual(usage.weekly.map(\.name), ["All models", "Fable"])
    }

    /// The CLI writes the reset without a year, so it has to be inferred. Taking
    /// the current year blindly reads a January reset as eleven months past.
    func testTheResetTimeIsReadAndTheYearInferred() throws {
        let now = Date(timeIntervalSince1970: 1_785_500_000) // 2026-07-31 in UTC
        let usage = try XCTUnwrap(PlanUsageParser.parse(real, now: now))
        let session = try XCTUnwrap(usage.session.first)
        let resetsAt = try XCTUnwrap(session.resetsAt)
        XCTAssertGreaterThan(resetsAt, now.addingTimeInterval(-86_400))
        XCTAssertLessThan(resetsAt.timeIntervalSince(now), 86_400 * 2)
    }

    /// "Resets in 18 min" near the boundary, the CLI's own words further out —
    /// "in 6 days" is less useful than a date with a timezone on it.
    func testResetsReadRelativeOnlyWithinADay() {
        let now = Date(timeIntervalSince1970: 1_785_500_000)
        let soon = PlanUsage.Limit(
            scope: .session, name: "Current session", fraction: 0.2,
            resetsText: "later", resetsAt: now.addingTimeInterval(18 * 60)
        )
        XCTAssertEqual(soon.resetDescription(now: now), "Resets in 18 min")

        let farOff = PlanUsage.Limit(
            scope: .week, name: "All models", fraction: 0.03,
            resetsText: "Aug 7 at 9am (Asia/Bangkok)", resetsAt: now.addingTimeInterval(6 * 86_400)
        )
        XCTAssertEqual(farOff.resetDescription(now: now), "Resets Aug 7 at 9am (Asia/Bangkok)")
    }

    /// Only the tier is taken out of `claude auth status`. That reply also
    /// carries the account's email and organisation id, which this app has no
    /// reason to hold.
    func testThePlanNameComesFromAuthStatus() {
        let json = """
        {"loggedIn":true,"authMethod":"claude.ai","email":"someone@example.com","subscriptionType":"max"}
        """
        XCTAssertEqual(PlanIdentityParser.planName(fromAuthStatus: json), "Max")
        XCTAssertNil(PlanIdentityParser.planName(fromAuthStatus: "{}"))
        XCTAssertNil(PlanIdentityParser.planName(fromAuthStatus: "not json"))
    }

    /// The prose around the numbers is not a limit and must not become a row —
    /// especially the "83% of your usage was at >150k context" line, which is a
    /// percentage of something else entirely.
    func testProseIsNotMistakenForALimit() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse(real))
        XCTAssertFalse(
            usage.limits.contains { $0.name.contains("context") || $0.fraction == 0.83 },
            "Got: \(usage.limits.map(\.name))"
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
            PlanUsage.Limit(scope: .week, name: "x", fraction: 0.256, resetsText: nil, resetsAt: nil).percentText,
            "26% used"
        )
    }
}
