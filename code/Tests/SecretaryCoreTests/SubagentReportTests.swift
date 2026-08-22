import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

@MainActor
final class SubagentReportTests: XCTestCase {
    private func makeSecretary(_ events: [ChatStreamEvent]) -> Secretary {
        Secretary(
            stateMachine: AssistantStateMachine(),
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            chatProvider: FakeChatProvider(.events(events))
        )
    }

    private func said(_ secretary: Secretary, _ needle: String) -> Bool {
        secretary.transcript.contains { $0.text.contains(needle) }
    }

    private let counting = SubagentTask(
        id: "t1",
        kind: "general-purpose",
        detail: "Count files in cwd"
    )

    private func finished(_ summary: String) -> ChatStreamEvent {
        .subagentFinished(SubagentOutcome(id: "t1", status: "completed", summary: summary))
    }

    private var done: ChatStreamEvent { .completed(stopReason: .none(), usage: .none()) }

    func testStartingASubagentIsAnnouncedInTheConversation() async {
        let secretary = makeSecretary([.subagentStarted(counting), done])
        secretary.submit("count the files")
        await settle()

        XCTAssertTrue(said(secretary, "Started a general-purpose sub-agent"))
        XCTAssertTrue(said(secretary, "Count files in cwd"))
    }

    func testTheAnswerIsReportedWithoutBeingAskedFor() async {
        let secretary = makeSecretary([.subagentStarted(counting), finished("3"), done])
        secretary.submit("count the files")
        await settle()

        XCTAssertTrue(said(secretary, "The general-purpose sub-agent finished"))
        XCTAssertTrue(said(secretary, "3"), "The sub-agent's own summary is the answer")
    }

    func testAFinishWithNoSummaryStillSpeaks() async {
        let secretary = makeSecretary([.subagentStarted(counting), finished(""), done])
        secretary.submit("count the files")
        await settle()

        XCTAssertTrue(said(secretary, "finished without a summary"))
    }

    func testWhileItRunsSheKnowsWhatIsRunning() async {
        let secretary = makeSecretary([.subagentStarted(counting), done])
        secretary.submit("count the files")
        await settle()

        let running = secretary.runningSubagent.toOptional()
        XCTAssertEqual(running?.task.kind, "general-purpose")
        XCTAssertEqual(running?.task.detail, "Count files in cwd")
    }

    func testProgressUpdatesTheHeaderRatherThanTheConversation() async {
        let stepping = SubagentTask(
            id: "t1",
            kind: "general-purpose",
            detail: "Running Count top-level files",
            lastTool: .some("Bash")
        )
        let secretary = makeSecretary([
            .subagentStarted(counting), .subagentProgress(stepping), done,
        ])
        secretary.submit("count the files")
        await settle()

        XCTAssertEqual(secretary.runningSubagent.toOptional()?.task.detail, "Running Count top-level files")
        XCTAssertFalse(
            said(secretary, "Running Count top-level files"),
            "Progress belongs in the header, not as its own paragraph"
        )
    }

    func testTheBadgeClearsWhenItEnds() async {
        let secretary = makeSecretary([.subagentStarted(counting), finished("3"), done])
        secretary.submit("count the files")
        await settle()

        XCTAssertFalse(secretary.runningSubagent.isDefined)
    }

    private func settle() async {
        for _ in 0..<40 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
