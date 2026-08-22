import XCTest
@testable import SecretaryCore

final class PlanUsageTests: XCTestCase {
    private let real = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 25% used · resets Jul 31 at 1:59pm (Asia/Bangkok)
    Current week (all models): 3% used · resets Aug 7 at 8:59am (Asia/Bangkok)
    Current week (Fable): 0% used

    What's contributing to your limits usage?
    Approximate, based on local sessions on this machine — does not include other devices.

    Last 24h · 510 requests · 11 sessions
      83% of your usage was at >150k context
      Top skills: /artifact-design 2%

    Last 7d · 3,428 requests · 105 sessions
      85% of your usage was at >150k context
      83% of your usage came from sessions active for 8+ hours
      Top plugins: superpowers 1%
    """

    func testItReadsTheRequestAndSessionCounts() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse(real))
        XCTAssertEqual(usage.activity.count, 2)
        XCTAssertEqual(usage.activity[0].period, "Last 24h")
        XCTAssertEqual(usage.activity[0].requests, 510)
        XCTAssertEqual(usage.activity[0].sessions, 11)
        XCTAssertEqual(usage.activity[1].requests, 3_428)
        XCTAssertEqual(usage.activity[1].sessions, 105)
    }

    func testTheBehaviourNotesRideAlongWithTheirPeriod() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse(real))
        XCTAssertEqual(usage.activity[0].notes, ["83% of your usage was at >150k context"])
        XCTAssertEqual(usage.activity[1].notes.count, 2)
        XCTAssertTrue(usage.activity[1].notes[1].contains("8+ hours"))
    }

    func testSkillAndPluginNamesAreDropped() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse(real))
        let notes = usage.activity.flatMap(\.notes).joined(separator: " ")
        XCTAssertFalse(notes.contains("artifact-design"), notes)
        XCTAssertFalse(notes.contains("superpowers"), notes)
    }

    func testTheLimitsSurviveWithoutAnActivityBlock() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse("Current session: 4% used"))
        XCTAssertEqual(usage.limits.count, 1)
        XCTAssertTrue(usage.activity.isEmpty)
    }

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

    func testTheSessionAndWeeklyWindowsAreSeparated() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse(real))
        XCTAssertEqual(usage.session.map(\.name), ["Current session"])
        XCTAssertEqual(usage.weekly.map(\.name), ["All models", "Fable"])
    }

    func testTheResetTimeIsReadAndTheYearInferred() throws {
        let the31stOfJuly2026InUTC = Date(timeIntervalSince1970: 1_785_500_000)
        let now = the31stOfJuly2026InUTC
        let usage = try XCTUnwrap(PlanUsageParser.parse(real, now: now))
        let session = try XCTUnwrap(usage.session.first)
        let resetsAt = try XCTUnwrap(session.resetsAt)
        XCTAssertGreaterThan(resetsAt, now.addingTimeInterval(-86_400))
        XCTAssertLessThan(resetsAt.timeIntervalSince(now), 86_400 * 2)
    }

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

    func testThePlanNameComesFromAuthStatus() {
        let json = """
        {"loggedIn":true,"authMethod":"claude.ai","email":"someone@example.com","subscriptionType":"max"}
        """
        XCTAssertEqual(PlanIdentityParser.planName(fromAuthStatus: json), "Max")
        XCTAssertNil(PlanIdentityParser.planName(fromAuthStatus: "{}"))
        XCTAssertNil(PlanIdentityParser.planName(fromAuthStatus: "not json"))
    }

    func testProseIsNotMistakenForALimit() throws {
        let usage = try XCTUnwrap(PlanUsageParser.parse(real))
        XCTAssertFalse(
            usage.limits.contains { $0.name.contains("context") || $0.fraction == 0.83 },
            "Got: \(usage.limits.map(\.name))"
        )
    }

    func testUnrecognisedOutputYieldsNothing() {
        XCTAssertNil(PlanUsageParser.parse(""))
        XCTAssertNil(PlanUsageParser.parse("Not logged in."))
        XCTAssertNil(PlanUsageParser.parse("Session usage is at three quarters."))
    }

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
