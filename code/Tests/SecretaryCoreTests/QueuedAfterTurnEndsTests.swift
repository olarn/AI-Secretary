import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

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

    func testAnsweringAfterTheTurnEndedStillStartsTheMessage() async {
        let secretary = makeSecretary()
        makeBusy()
        secretary.submit("what is 2+2?")
        finishTheTurn()

        secretary.resolveInterruption(.wait)
        await settle()

        XCTAssertTrue(
            said(secretary, "Now, the one that was waiting:"),
            "The queued message must start once nothing is in its way"
        )
        XCTAssertTrue(secretary.queuedMessages.isEmpty, "Nothing should still be waiting")
    }

    func testWhileSheIsStillBusyItReallyDoesWait() {
        let secretary = makeSecretary()
        makeBusy()
        secretary.submit("what is 2+2?")

        secretary.resolveInterruption(.wait)

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
