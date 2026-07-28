import FunctionalCore
import XCTest
@testable import AssistantState

final class AssistantStateReducerTests: XCTestCase {
    /// Walk the table by folding each step into the next, so a broken
    /// transition shows up as the state it stopped at rather than a crash.
    func testFullHappyPathToSuccess() {
        let path: [(AssistantEvent, AssistantState)] = [
            (.userBeganInput, .listening),
            (.beginInterpreting, .thinking),
            (.beginExecuting, .working),
            (.succeeded, .success),
            (.acknowledge, .idle)
        ]

        let reached = path.reduce(Option.some(AssistantState.idle)) { state, step in
            state.flatMap { nextAssistantState(from: $0, on: step.0) }^
        }

        XCTAssertEqual(reached, .some(.idle))

        var state = AssistantState.idle
        for (event, expected) in path {
            state = nextAssistantState(from: state, on: event).getOrElse(state)
            XCTAssertEqual(state, expected)
        }
    }

    func testWorkingToErrorToIdle() {
        XCTAssertEqual(nextAssistantState(from: .working, on: .failed), .some(.error))
        XCTAssertEqual(nextAssistantState(from: .error, on: .acknowledge), .some(.idle))
    }

    func testInvalidTransitionsAreNone() {
        let rejected: [(AssistantState, AssistantEvent)] = [
            (.idle, .beginInterpreting),
            (.idle, .beginExecuting),
            (.listening, .beginExecuting),
            (.thinking, .succeeded),
            (.success, .userBeganInput),
            (.error, .userBeganInput),
            (.working, .userBeganInput)
        ]

        for (state, event) in rejected {
            XCTAssertEqual(
                nextAssistantState(from: state, on: event),
                Option.none(),
                "\(state) + \(event) must not transition"
            )
        }
    }

    func testDecideTransitionPutsTheRejectionOnTheLeftRail() {
        XCTAssertEqual(decideTransition(from: .idle, on: .userBeganInput), .right(.listening))
        XCTAssertEqual(
            decideTransition(from: .idle, on: .succeeded),
            .left(.invalidTransition(from: .idle, event: .succeeded))
        )
    }
}

final class AssistantStateMachineTests: XCTestCase {
    func testSendAppliesValidTransitionAndRecordsHistory() {
        let machine = AssistantStateMachine()

        let result = machine.send(.userBeganInput, reason: "user opened chat", taskID: .some("task-1"))

        XCTAssertEqual(result, .right(.listening))
        XCTAssertEqual(machine.state, .listening)
        XCTAssertEqual(machine.history.count, 1)

        let recorded = machine.history[0]
        XCTAssertEqual(recorded.from, .idle)
        XCTAssertEqual(recorded.to, .listening)
        XCTAssertEqual(recorded.reason, "user opened chat")
        XCTAssertEqual(recorded.taskID, .some("task-1"))
    }

    func testSendRejectsInvalidTransitionAndLeavesStateUnchanged() {
        let machine = AssistantStateMachine()

        let result = machine.send(.succeeded, reason: "should not apply")

        XCTAssertEqual(result, .left(.invalidTransition(from: .idle, event: .succeeded)))
        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(machine.history.isEmpty)
    }

    func testActiveTaskIDClearsOnReturnToIdle() {
        let machine = AssistantStateMachine()
        machine.send(.userBeganInput, reason: "start", taskID: .some("task-42"))
        machine.send(.beginInterpreting, reason: "interpret")
        machine.send(.beginExecuting, reason: "execute")
        XCTAssertEqual(machine.activeTaskID, .some("task-42"))

        machine.send(.succeeded, reason: "done")
        machine.send(.acknowledge, reason: "user dismissed")

        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.activeTaskID, Option.none())
        XCTAssertEqual(machine.history.count, 5)
    }
}
