import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

/// The history menu, end to end through the Secretary.
///
/// The thing these guard is the one that can't be seen in a screenshot: a
/// reopened conversation puts the whole thread back on screen, so if the
/// model's side of it didn't come back too, every answer after that is written
/// by someone who can't see what the person is looking at. Content and context
/// are two claims, and only one of them is visible.
@MainActor
final class ChatHistoryTests: XCTestCase {
    private let machine = AssistantStateMachine()

    private func makeSecretary(
        provider: SpyWorkspaceProvider,
        store: ConversationStoring = InMemoryConversationStore()
    ) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            activityPreference: InMemoryActivityPreference(),
            chatProvider: provider,
            conversationStore: store
        )
    }

    private func waitUntilSettled() async {
        let deadline = Date().addingTimeInterval(2)
        while machine.state.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// One complete turn, so the transcript holds a real exchange.
    private func exchange(_ secretary: Secretary, _ text: String) async {
        secretary.submit(text)
        await waitUntilSettled()
    }

    // MARK: - Putting one away

    func testNewConversationFilesTheOldOneAndClearsTheScreen() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "summarise my notes")

        secretary.newConversation()

        XCTAssertEqual(secretary.history.count, 1)
        XCTAssertEqual(secretary.history.first?.title, "summarise my notes")
        XCTAssertTrue(
            secretary.history.first?.entries.contains { $0.text == "summarise my notes" } == true,
            "The archived copy has to hold the words, not just a name"
        )
        // The screen is the new conversation's, not the old one's.
        XCTAssertFalse(secretary.transcript.contains { $0.text == "summarise my notes" })
        XCTAssertEqual(secretary.transcript.filter { $0.kind == .divider }.count, 1)
    }

    /// The whole feature rests on this: what the model remembers lives on
    /// Claude Code's side and can only be recovered by name.
    func testTheSessionIsArchivedWithTheWords() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "hello")
        provider.currentSessionID = "session-abc"

        secretary.newConversation()

        XCTAssertEqual(secretary.history.first?.sessionID, Option.some("session-abc"))
    }

    /// Pressing New Conversation on a fresh app must not leave a row behind.
    func testAnEmptyConversationIsNotArchived() {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())
        secretary.newConversation()
        secretary.newConversation()
        XCTAssertTrue(secretary.history.isEmpty)
    }

    func testTheOldestFallsOffOnceTenAreKept() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())
        for i in 1...12 {
            await exchange(secretary, "chat number \(i)")
            secretary.newConversation()
        }

        XCTAssertEqual(secretary.history.count, 10)
        XCTAssertEqual(secretary.history.first?.title, "chat number 12")
        XCTAssertFalse(secretary.history.contains { $0.title == "chat number 1" })
    }

    // MARK: - Reopening one

    func testReopeningRestoresTheWordsAndTheSession() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "the vault question")
        provider.currentSessionID = "session-vault"
        secretary.newConversation()
        let archived = try! XCTUnwrap(secretary.history.first)

        await exchange(secretary, "something unrelated")
        secretary.resumeConversation(archived.id)

        XCTAssertTrue(
            secretary.transcript.contains { $0.text == "the vault question" },
            "The words come back"
        )
        XCTAssertFalse(
            secretary.transcript.contains { $0.text == "something unrelated" },
            "and the conversation it replaced does not linger"
        )
        XCTAssertEqual(
            provider.adoptedSessions.last, "session-vault",
            "and Claude Code is told to carry on with that thread, not a new one"
        )
    }

    /// Reopening is not a way to lose the conversation you were in.
    func testReopeningFilesTheConversationItReplaces() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "first thread")
        secretary.newConversation()
        let first = try! XCTUnwrap(secretary.history.first)

        await exchange(secretary, "second thread")
        secretary.resumeConversation(first.id)

        XCTAssertEqual(secretary.history.count, 2)
        XCTAssertTrue(secretary.history.contains { $0.title == "second thread" })
    }

    /// Reopen, talk, put away again — one row, not two. Otherwise the menu
    /// fills with copies of the conversation you keep coming back to.
    func testAReopenedConversationKeepsItsPlaceRatherThanForking() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "ongoing thread")
        secretary.newConversation()
        let original = try! XCTUnwrap(secretary.history.first)

        secretary.resumeConversation(original.id)
        await exchange(secretary, "one more thing")
        secretary.newConversation()

        XCTAssertEqual(secretary.history.count, 1)
        XCTAssertEqual(secretary.history.first?.id, original.id)
        XCTAssertEqual(secretary.history.first?.title, "ongoing thread", "The name doesn't drift")
        XCTAssertTrue(
            secretary.history.first?.entries.contains { $0.text == "one more thing" } == true,
            "and the row holds the continued conversation, not the one from before"
        )
    }

    /// A conversation that never reached the model must not claim it can carry
    /// on — and must not ask Claude Code to resume a session that never existed.
    func testReopeningSaysSoWhenThereIsNothingToCarryOnFrom() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "never got a session")
        provider.currentSessionID = nil
        secretary.newConversation()

        secretary.resumeConversation(try! XCTUnwrap(secretary.history.first).id)

        XCTAssertEqual(provider.adoptedSessions.last, String?.none)
        XCTAssertTrue(
            secretary.transcript.last?.text.contains("I don't remember it") == true,
            "Got: \(secretary.transcript.last?.text ?? "-")"
        )
    }

    /// Reopening the conversation already on screen must not wipe it and file a
    /// second copy of itself.
    func testReopeningTheOneYouAreAlreadyInDoesNothing() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "current thread")
        secretary.newConversation()
        let id = try! XCTUnwrap(secretary.history.first).id

        secretary.resumeConversation(id)
        let after = secretary.transcript
        secretary.resumeConversation(id)

        XCTAssertEqual(secretary.history.count, 1)
        XCTAssertEqual(secretary.transcript.map(\.text), after.map(\.text))
    }

    func testReopeningSomethingThatIsNotThereChangesNothing() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())
        await exchange(secretary, "hello")
        let before = secretary.transcript.map(\.text)

        secretary.resumeConversation(UUID())

        XCTAssertEqual(secretary.transcript.map(\.text), before)
        XCTAssertTrue(secretary.history.isEmpty)
    }

    // MARK: - The turn after reopening

    /// The proof that context came back: after reopening, the next turn resumes
    /// rather than starting over. `resetConversation` is what would throw the
    /// thread away, and it must not be called on this path.
    func testTheTurnAfterReopeningContinuesTheOldSession() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "remember this")
        provider.currentSessionID = "session-keep"
        secretary.newConversation()

        secretary.resumeConversation(try! XCTUnwrap(secretary.history.first).id)
        // Counted from *after* the adopt: clearing the slate on the way in is
        // the point, throwing the thread away on the way out is the bug.
        let resets = provider.resetCount
        await exchange(secretary, "and now?")

        XCTAssertEqual(provider.currentSessionID, "session-keep")
        XCTAssertEqual(provider.resetCount, resets, "Nothing may drop the session after it was adopted")
    }

    /// The dangerous case, and the reason `sessionLost` exists: the thread is on
    /// screen but Claude Code no longer has it. Saying nothing would leave every
    /// following answer looking like the app ignoring what is plainly visible.
    func testALostSessionIsAnnouncedInTheTranscript() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "old thread")
        provider.currentSessionID = "session-expired"
        secretary.newConversation()
        secretary.resumeConversation(try! XCTUnwrap(secretary.history.first).id)

        provider.eventsForNextTurn = [
            .sessionLost,
            .textDelta("Starting fresh."),
            .completed(stopReason: .none(), usage: .none())
        ]
        await exchange(secretary, "carry on")

        XCTAssertTrue(
            secretary.transcript.contains { $0.text.contains("lost my memory of everything above") },
            "Got: \(secretary.transcript.map(\.text))"
        )
    }

    /// Once the memory is gone, the live conversation is no longer that archived
    /// one — putting it away must not overwrite the original with a thread the
    /// model never actually continued.
    func testALostSessionUnlinksTheLiveChatFromItsArchivedRow() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "old thread")
        provider.currentSessionID = "session-expired"
        secretary.newConversation()
        secretary.resumeConversation(try! XCTUnwrap(secretary.history.first).id)

        provider.eventsForNextTurn = [
            .sessionLost,
            .textDelta("Starting fresh."),
            .completed(stopReason: .none(), usage: .none())
        ]
        await exchange(secretary, "carry on")
        secretary.newConversation()

        XCTAssertEqual(secretary.history.count, 2, "The original row survives beside the new thread")
    }

    // MARK: - Clearing

    func testClearAllEmptiesTheMenuButLeavesTheChatOnScreen() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())
        await exchange(secretary, "one")
        secretary.newConversation()
        await exchange(secretary, "two")

        secretary.clearHistory()

        XCTAssertTrue(secretary.history.isEmpty)
        XCTAssertTrue(secretary.transcript.contains { $0.text == "two" }, "The live chat is not history")
    }

    // MARK: - Across launches

    /// A history that emptied itself on relaunch would be a list of things you
    /// could already scroll to.
    func testHistorySurvivesARestart() async {
        let store = InMemoryConversationStore()
        let first = makeSecretary(provider: SpyWorkspaceProvider(), store: store)
        await exchange(first, "yesterday's question")
        first.newConversation()

        let relaunched = makeSecretary(provider: SpyWorkspaceProvider(), store: store)

        XCTAssertEqual(relaunched.history.map(\.title), ["yesterday's question"])
        XCTAssertTrue(relaunched.historyRows().first?.label.hasPrefix("yesterday's question") == true)
    }

    /// A Secretary built without being told where to keep history must not
    /// reach the person's own file.
    ///
    /// It did, and the first full run of this suite wrote nine test
    /// conversations into it. The tests that caused it were about queues and
    /// interruptions and had no idea a history existed — which is the point: a
    /// default that reaches real data is one every future test has to remember
    /// to override.
    func testTheDefaultStoreIsNotTheOwnersOwnFile() async {
        let before = try? Data(contentsOf: FileConversationStore.defaultURL)

        let secretary = Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            activityPreference: InMemoryActivityPreference(),
            chatProvider: SpyWorkspaceProvider()
        )
        await exchange(secretary, "a test conversation")
        secretary.newConversation()

        XCTAssertEqual(secretary.history.count, 1, "it still keeps history, just not there")
        XCTAssertEqual(
            try? Data(contentsOf: FileConversationStore.defaultURL), before,
            "the file on disk must be byte-for-byte what it was"
        )
    }

    // MARK: - /history

    func testTheSlashCommandListsAndReopens() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "the first one")
        secretary.newConversation()

        secretary.submit("/history")
        XCTAssertTrue(
            secretary.transcript.last?.text.contains("1. the first one") == true,
            "Got: \(secretary.transcript.last?.text ?? "-")"
        )

        secretary.submit("/history 1")
        XCTAssertTrue(secretary.transcript.contains { $0.text == "the first one" })
    }

    func testTheSlashCommandRefusesANumberThatIsNotThere() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())
        await exchange(secretary, "only one")
        secretary.newConversation()

        secretary.submit("/history 7")

        XCTAssertTrue(
            secretary.transcript.last?.text.contains("between 1 and 1") == true,
            "Got: \(secretary.transcript.last?.text ?? "-")"
        )
    }

    func testTheSlashCommandSaysWhenThereIsNothingYet() {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())
        secretary.submit("/history")
        XCTAssertTrue(
            secretary.transcript.last?.text.contains("No past conversations yet") == true,
            "Got: \(secretary.transcript.last?.text ?? "-")"
        )
    }
}
