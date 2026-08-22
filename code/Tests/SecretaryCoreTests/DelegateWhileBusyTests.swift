import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

@MainActor
final class DelegateWhileBusyTests: XCTestCase {
    private let machine = AssistantStateMachine()
    private let anya = UUID()
    private let ditto = UUID()

    private func card(_ id: UUID, _ name: String, busy: Bool) -> CharacterCard {
        CharacterCard(id: id, name: name, model: "Default", effort: "medium", isBusy: busy)
    }

    private func makeSecretary(directory: @escaping () -> [CharacterCard]) -> Secretary {
        let secretary = Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            chatProvider: FakeChatProvider(.events([.completed(stopReason: .none(), usage: .none())]))
        )
        secretary.directorySnapshot = directory
        return secretary
    }

    private func makeBusy() {
        machine.send(.userBeganInput, reason: "test")
        machine.send(.beginInterpreting, reason: "test")
        machine.send(.beginExecuting, reason: "test")
    }

    private func said(_ secretary: Secretary, _ needle: String) -> Bool {
        secretary.transcript.contains { $0.text.contains(needle) }
    }

    func testOnlyTheFreeOnesAreOffered() {
        let directory = [card(anya, "อาเนีย", busy: false), card(ditto, "Ditto", busy: true)]
        XCTAssertEqual(delegationCandidates(directory).map(\.name), ["อาเนีย"])
    }

    func testNobodyFreeMeansNoChoice() {
        XCTAssertTrue(delegationCandidates([card(ditto, "Ditto", busy: true)]).isEmpty)
        XCTAssertTrue(delegationCandidates([]).isEmpty)
    }

    func testTheCardIsDrawnWithWhoeverWasFree() {
        let secretary = makeSecretary { [self.card(self.anya, "อาเนีย", busy: false)] }
        makeBusy()
        secretary.submit("what is 2+2?")

        guard case .interruption(_, _, let candidates) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected the card, got \(secretary.pendingDecision)")
        }
        XCTAssertEqual(candidates.map(\.name), ["อาเนีย"])
    }

    func testDelegatingSendsTheWorkAndSaysSo() {
        let free = card(anya, "อาเนีย", busy: false)
        let secretary = makeSecretary { [free] }
        var sent: [CharacterMessage] = []
        secretary.onSend = { sent.append($0) }

        makeBusy()
        secretary.submit("what is 2+2?")
        secretary.resolveInterruption(.delegate(to: free))

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.to, anya)
        XCTAssertEqual(sent.first?.body, "what is 2+2?")
        XCTAssertTrue(said(secretary, chosenLine("Give it to อาเนีย")))
    }

    func testSheMayHaveStartedSomethingSinceTheCardWasDrawn() {
        let free = card(anya, "อาเนีย", busy: false)
        var busyNow = false
        let secretary = makeSecretary { [self.card(self.anya, "อาเนีย", busy: busyNow)] }
        var sent: [CharacterMessage] = []
        secretary.onSend = { sent.append($0) }

        makeBusy()
        secretary.submit("what is 2+2?")
        let sheStartsSomethingWhileWeDecide = true
        busyNow = sheStartsSomethingWhileWeDecide
        secretary.resolveInterruption(.delegate(to: free))

        XCTAssertTrue(sent.isEmpty, "Nothing may be handed to someone who is no longer free")
        XCTAssertTrue(said(secretary, "started something else just now"))
    }

    func testARefusedHandOverAsksAgainRatherThanDroppingIt() {
        let free = card(anya, "อาเนีย", busy: false)
        var busyNow = false
        let secretary = makeSecretary { [self.card(self.anya, "อาเนีย", busy: busyNow)] }

        makeBusy()
        secretary.submit("what is 2+2?")
        busyNow = true
        secretary.resolveInterruption(.delegate(to: free))

        guard case .interruption(let text, _, let candidates) = secretary.pendingDecision.toOptional() else {
            return XCTFail("The card must come back, not vanish")
        }
        XCTAssertEqual(text, "what is 2+2?")
        XCTAssertTrue(candidates.isEmpty, "She is busy now, so she is no longer offered")
    }

    func testTheControlDoesNotNameAnybodyUntilItIsOpened() {
        XCTAssertEqual(CardChoice.giveItToSomeone, "Give it to…")
        for name in ["อาเนีย", "Ditto", "Miku (2nd Brain)"] {
            XCTAssertFalse(
                CardChoice.giveItToSomeone.contains(name),
                "The control is one control; names live inside it"
            )
        }
    }

    func testTheProsePathStillAcceptsABusyRecipient() {
        let busy = card(ditto, "Ditto", busy: true)
        let message = CharacterMessage(
            from: UUID(), fromName: "Pikachu", to: ditto, kind: .errand, body: "x"
        )
        let viaProse = relayDeliverable(
            message, known: [ditto], outstanding: [], recipientName: "Ditto"
        )
        XCTAssertTrue(viaProse.isRight, "A busy recipient still takes a prose errand")

        let viaButton = delegationDeliverable(
            message, known: [ditto], outstanding: [], recipient: busy
        )
        XCTAssertTrue(viaButton.isLeft, "The button promises she is free, so it refuses")
    }
}
