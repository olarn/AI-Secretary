import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

/// Answering "wait its turn" after the turn has already ended.
///
/// The card waits as long as the person does, so the turn finishing underneath
/// it is ordinary rather than exotic. The queue is pumped when a turn ends —
/// and that moment had already passed, so the message sat there for ever under
/// a badge reading 1, after she had said out loud that she would come to it.
/// Found by driving 0.18.282.
@MainActor
final class QueuedAfterTurnEndsTests: XCTestCase {
    private let machine = AssistantStateMachine()

    private func makeSecretary() -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            chatProvider: FakeChatProvider(.events([.completed(stopReason: .none(), usage: .none())]))
        )
    }

    /// Drives the machine the way a real turn does, so `routeToTurn` sees a busy
    /// character and raises the card rather than starting the message.
    private func makeBusy() {
        machine.send(.userBeganInput, reason: "test")
        machine.send(.beginInterpreting, reason: "test")
        machine.send(.beginExecuting, reason: "test")
    }

    private func finishTheTurn() {
        machine.send(.succeeded, reason: "test")
    }

    private func said(_ secretary: Secretary, _ needle: String) -> Bool {
        secretary.transcript.contains { $0.text.contains(needle) }
    }

    func testTheCardAppearsWhileSheIsBusy() {
        let secretary = makeSecretary()
        makeBusy()
        secretary.submit("what is 2+2?")

        guard case .interruption? = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected the interruption card, got \(secretary.pendingDecision)")
        }
    }

    /// The bug. Answer the card after the work it was interrupting has already
    /// finished, and the queued message has to start — not wait for a turn
    /// boundary that has been and gone.
    func testAnsweringAfterTheTurnEndedStillStartsTheMessage() async {
        let secretary = makeSecretary()
        makeBusy()
        secretary.submit("what is 2+2?")
        finishTheTurn()

        secretary.resolveInterruption(queue: true)
        await settle()

        XCTAssertTrue(
            said(secretary, "Now, the one that was waiting:"),
            "The queued message must start once nothing is in its way"
        )
        XCTAssertTrue(secretary.queuedMessages.isEmpty, "Nothing should still be waiting")
    }

    /// The other half, unchanged: while she is genuinely still busy, it waits.
    /// Dispatching here would start two turns at once.
    func testWhileSheIsStillBusyItReallyDoesWait() {
        let secretary = makeSecretary()
        makeBusy()
        secretary.submit("what is 2+2?")

        secretary.resolveInterruption(queue: true)

        XCTAssertEqual(secretary.queuedMessages.count, 1)
        XCTAssertFalse(said(secretary, "Now, the one that was waiting:"))
    }

    private func settle() async {
        for _ in 0..<40 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
