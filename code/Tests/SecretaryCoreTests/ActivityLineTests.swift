import XCTest
import LLMProvider
@testable import SecretaryCore

/// Whose work each line of the activity box is.
final class ActivityLineTests: XCTestCase {

    func testHerOwnStepsKeepTheMarkersTheyAlwaysHad() {
        XCTAssertEqual(
            activityLine(AgentActivity(kind: .thinking, detail: "Thinking")),
            "◇ Thinking"
        )
        XCTAssertEqual(
            activityLine(AgentActivity(kind: .tool, detail: "Bash: ls")),
            "▸ Bash: ls"
        )
    }

    /// The bug, as a test. A sub-agent's inner `Bash` was drawn exactly like one
    /// she had run herself, so the box reported a command she never ran and
    /// nothing on screen could contradict it.
    func testASubagentsStepIsMarkedAsNotHers() {
        let hers = activityLine(AgentActivity(kind: .tool, detail: "Bash: ls"))
        let theirs = activityLine(
            AgentActivity(kind: .tool, detail: "Bash: ls", origin: .subagent("toolu_1"))
        )
        XCTAssertNotEqual(hers, theirs, "The two must not be indistinguishable")
        XCTAssertEqual(theirs, "   ▹ Bash: ls")
    }

    func testASubagentThinkingIsMarkedToo() {
        XCTAssertEqual(
            activityLine(AgentActivity(kind: .thinking, detail: "Thinking", origin: .subagent("t"))),
            "   ◈ Thinking"
        )
    }

    /// Indented, so the sub-agent's steps read as nested under whatever of hers
    /// started them rather than as a second list at the same level.
    func testSubagentLinesAreIndentedUnderHers() {
        let theirs = activityLine(
            AgentActivity(kind: .tool, detail: "x", origin: .subagent("t"))
        )
        XCTAssertTrue(theirs.hasPrefix(" "), "A sub-agent's step sits under hers")
    }
}
