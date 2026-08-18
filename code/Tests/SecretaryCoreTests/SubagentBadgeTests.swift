import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
@testable import SecretaryCore

/// The one line the header shows about a running sub-agent.
final class SubagentBadgeTests: XCTestCase {

    func testWhileItIsAnsweringItJustSaysWhatItIsDoing() {
        XCTAssertEqual(
            subagentBadgeText(detail: "Counting files", lastTool: nil, liveness: .running),
            "Counting files"
        )
    }

    /// The tool it last reached for is what makes a long silence read as a slow
    /// command rather than a fault.
    func testTheToolItIsWaitingOnIsNamed() {
        XCTAssertEqual(
            subagentBadgeText(detail: "Counting files", lastTool: "Bash", liveness: .running),
            "Counting files · Bash"
        )
    }

    func testQuietSaysHowLong() {
        XCTAssertEqual(
            subagentBadgeText(detail: "Counting files", lastTool: "Bash", liveness: .quiet(45)),
            "Counting files · Bash — quiet 45s"
        )
    }

    /// **Never the word failed.** Nothing on this side can know that: a
    /// sub-agent on one slow tool call is indistinguishable from a dead one, and
    /// a guess here would be believed.
    func testTheLostCaseReportsSilenceAndNeverFailure() {
        let text = subagentBadgeText(detail: "Counting files", lastTool: nil, liveness: .presumedLost)
        XCTAssertEqual(text, "Counting files — nothing for a while")
        for forbidden in ["fail", "died", "dead", "error", "crashed", "lost"] {
            XCTAssertFalse(
                text.lowercased().contains(forbidden),
                "The badge must not claim \(forbidden) — it cannot know"
            )
        }
    }

    /// A sub-agent with no description of its own still has to be nameable, or
    /// the badge appears as an empty capsule.
    func testWithoutADescriptionItFallsBackToTheKind() {
        let running = RunningSubagent(
            task: SubagentTask(id: "t1", kind: "general-purpose", detail: ""),
            lastEventAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(
            running.badgeText(now: Date(timeIntervalSince1970: 1_800_000_000)),
            "general-purpose"
        )
    }

    /// Reads through the pair, which is the shape the header actually holds.
    func testThePairAgesFromItsOwnTimestamp() {
        let spoke = Date(timeIntervalSince1970: 1_800_000_000)
        let running = RunningSubagent(
            task: SubagentTask(id: "t1", kind: "general-purpose", detail: "Counting", lastTool: .some("Bash")),
            lastEventAt: spoke
        )
        XCTAssertEqual(running.badgeText(now: spoke), "Counting · Bash")
        XCTAssertEqual(running.badgeText(now: spoke.addingTimeInterval(60)), "Counting · Bash — quiet 60s")
    }
}
