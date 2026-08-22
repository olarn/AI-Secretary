import XCTest
import LLMProvider
@testable import SecretaryCore

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

    func testSubagentLinesAreIndentedUnderHers() {
        let theirs = activityLine(
            AgentActivity(kind: .tool, detail: "x", origin: .subagent("t"))
        )
        XCTAssertTrue(theirs.hasPrefix(" "), "A sub-agent's step sits under hers")
    }
}
