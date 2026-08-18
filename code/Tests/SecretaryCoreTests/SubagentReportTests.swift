import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

/// What the character says while a sub-agent works, and when it ends.
///
/// The complaint these were written for: she went silent for the whole of a
/// sub-agent's run, and said nothing when it finished — you had to ask again to
/// find out anything had happened.
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

    /// Said in the conversation, not only in the activity box — that box is off
    /// by default, and someone who never turned it on is exactly the person who
    /// cannot tell working from dead.
    func testStartingASubagentIsAnnouncedInTheConversation() async {
        let secretary = makeSecretary([.subagentStarted(counting), done])
        secretary.submit("count the files")
        await settle()

        XCTAssertTrue(said(secretary, "Started a general-purpose sub-agent"))
        XCTAssertTrue(said(secretary, "Count files in cwd"))
    }

    /// The heart of it: the answer arrives without being asked for.
    func testTheAnswerIsReportedWithoutBeingAskedFor() async {
        let secretary = makeSecretary([.subagentStarted(counting), finished("3"), done])
        secretary.submit("count the files")
        await settle()

        XCTAssertTrue(said(secretary, "The general-purpose sub-agent finished"))
        XCTAssertTrue(said(secretary, "3"), "The sub-agent's own summary is the answer")
    }

    /// A sub-agent that says nothing still has to be reported. Silence here is
    /// indistinguishable from the session having died, which is the bug.
    func testAFinishWithNoSummaryStillSpeaks() async {
        let secretary = makeSecretary([.subagentStarted(counting), finished(""), done])
        secretary.submit("count the files")
        await settle()

        XCTAssertTrue(said(secretary, "finished without a summary"))
    }

    // MARK: - What the header reads

    func testWhileItRunsSheKnowsWhatIsRunning() async {
        let secretary = makeSecretary([.subagentStarted(counting), done])
        secretary.submit("count the files")
        await settle()

        let running = secretary.runningSubagent.toOptional()
        XCTAssertEqual(running?.task.kind, "general-purpose")
        XCTAssertEqual(running?.task.detail, "Count files in cwd")
    }

    /// Progress moves the description without adding a line per step — the CLI
    /// sends one per step, and a paragraph each would bury the answer.
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

    /// The badge must not outlive the work it describes.
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
