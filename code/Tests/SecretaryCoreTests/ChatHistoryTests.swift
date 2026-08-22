import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

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

    private func exchange(_ secretary: Secretary, _ text: String) async {
        secretary.submit(text)
        await waitUntilSettled()
    }

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
        XCTAssertFalse(secretary.transcript.contains { $0.text == "summarise my notes" })
        XCTAssertEqual(secretary.transcript.filter { $0.kind == .divider }.count, 1)
    }

    func testTheSessionIsArchivedWithTheWords() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "hello")
        provider.currentSessionID = "session-abc"

        secretary.newConversation()

        XCTAssertEqual(secretary.history.first?.sessionID, Option.some("session-abc"))
    }

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

        let historyBefore = secretary.history.map(\.id)

        secretary.resumeConversation(UUID())

        XCTAssertEqual(secretary.transcript.map(\.text), before)
        XCTAssertEqual(secretary.history.map(\.id), historyBefore)
    }

    func testTheTurnAfterReopeningContinuesTheOldSession() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider: provider)
        await exchange(secretary, "remember this")
        provider.currentSessionID = "session-keep"
        secretary.newConversation()

        secretary.resumeConversation(try! XCTUnwrap(secretary.history.first).id)
        let resets = provider.resetCount
        await exchange(secretary, "and now?")

        XCTAssertEqual(provider.currentSessionID, "session-keep")
        XCTAssertEqual(provider.resetCount, resets, "Nothing may drop the session after it was adopted")
    }

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

    func testALostSessionKeepsOneRowForOneConversation() async {
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

        XCTAssertEqual(secretary.history.count, 1, "One conversation on screen is one row")
        XCTAssertTrue(
            secretary.history[0].entries.contains { $0.text.contains("Starting fresh") },
            "and it carries what was said after the memory went"
        )
    }

    func testTheConversationBeingHadIsInTheHistoryFromItsFirstTurn() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())

        await exchange(secretary, "what is the plan")

        XCTAssertEqual(secretary.history.count, 1)
        XCTAssertEqual(secretary.history.first?.title, "what is the plan")
    }

    func testTheLiveConversationIsTickedInTheMenu() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())

        await exchange(secretary, "hello")

        XCTAssertEqual(secretary.historyRows().map(\.isCurrent), [true])
    }

    func testFurtherTurnsUpdateTheSameRowRatherThanAddingOne() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())

        await exchange(secretary, "first")
        let id = secretary.history.first?.id
        await exchange(secretary, "second")

        XCTAssertEqual(secretary.history.count, 1)
        XCTAssertEqual(secretary.history.first?.id, id)
        XCTAssertTrue(secretary.history[0].entries.contains { $0.text == "second" })
    }

    func testANewConversationLeavesTheFiledOneBehind() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())
        await exchange(secretary, "first")

        secretary.newConversation()

        XCTAssertEqual(secretary.history.count, 1)
        XCTAssertEqual(secretary.historyRows().map(\.isCurrent), [false])
    }

    func testAnEmptyConversationIsNotFiled() {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())

        secretary.newConversation()
        secretary.newConversation()

        XCTAssertTrue(secretary.history.isEmpty)
    }

    func testClearAllEmptiesTheMenuButLeavesTheChatOnScreen() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())
        await exchange(secretary, "one")
        secretary.newConversation()
        await exchange(secretary, "two")

        secretary.clearHistory()

        XCTAssertTrue(secretary.history.isEmpty)
        XCTAssertTrue(secretary.transcript.contains { $0.text == "two" }, "The live chat is not history")
    }

    func testAFailedSaveIsStillOnScreenAfterTheClear() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider(), store: FailingConversationStore())
        await exchange(secretary, "a conversation worth keeping")

        secretary.newConversation()

        XCTAssertTrue(
            secretary.transcript.contains { $0.kind == .failure && $0.text.contains("couldn't save") },
            "Got: \(secretary.transcript.map(\.text))"
        )
    }

    func testHistorySurvivesARestart() async {
        let store = InMemoryConversationStore()
        let first = makeSecretary(provider: SpyWorkspaceProvider(), store: store)
        await exchange(first, "yesterday's question")
        first.newConversation()

        let relaunched = makeSecretary(provider: SpyWorkspaceProvider(), store: store)

        XCTAssertEqual(relaunched.history.map(\.title), ["yesterday's question"])
        XCTAssertTrue(relaunched.historyRows().first?.label.hasPrefix("yesterday's question") == true)
    }

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

    func testReopeningDoesNotArchiveTheCommandThatReopened() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())
        await exchange(secretary, "a real conversation")
        secretary.newConversation()

        secretary.submit("/history 1")
        secretary.newConversation()

        XCTAssertEqual(secretary.history.count, 1)
        XCTAssertFalse(
            secretary.history.contains { $0.title.hasPrefix("/") },
            "Got: \(secretary.history.map(\.title))"
        )
    }

    func testTheClosingCommandIsNotPartOfTheArchivedConversation() async {
        let secretary = makeSecretary(provider: SpyWorkspaceProvider())
        await exchange(secretary, "a real conversation")

        secretary.submit("/new")

        XCTAssertFalse(
            secretary.history.first?.entries.contains { $0.text == "/new" } == true,
            "Got: \(secretary.history.first?.entries.map(\.text) ?? [])"
        )
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

final class FailingConversationStore: ConversationStoring, @unchecked Sendable {
    func load() -> Either<ConversationStoreError, [ArchivedConversation]> { .right([]) }

    func save(_ conversations: [ArchivedConversation]) -> Either<ConversationStoreError, Void> {
        .left(.writeFailed(path: "/nowhere", message: "disk is full"))
    }
}
