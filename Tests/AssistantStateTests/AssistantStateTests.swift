import XCTest
@testable import AssistantState

final class AssistantStateReducerTests: XCTestCase {
    func testFullHappyPathToSuccess() {
        var state = AssistantState.idle

        state = AssistantStateReducer.nextState(from: state, on: .userBeganInput)!
        XCTAssertEqual(state, .listening)

        state = AssistantStateReducer.nextState(from: state, on: .beginInterpreting)!
        XCTAssertEqual(state, .thinking)

        state = AssistantStateReducer.nextState(from: state, on: .beginExecuting)!
        XCTAssertEqual(state, .working)

        state = AssistantStateReducer.nextState(from: state, on: .succeeded)!
        XCTAssertEqual(state, .success)

        state = AssistantStateReducer.nextState(from: state, on: .acknowledge)!
        XCTAssertEqual(state, .idle)
    }

    func testWorkingToErrorToIdle() {
        var state = AssistantState.working
        state = AssistantStateReducer.nextState(from: state, on: .failed)!
        XCTAssertEqual(state, .error)

        state = AssistantStateReducer.nextState(from: state, on: .acknowledge)!
        XCTAssertEqual(state, .idle)
    }

    func testInvalidTransitionsAreRejected() {
        XCTAssertNil(AssistantStateReducer.nextState(from: .idle, on: .beginInterpreting))
        XCTAssertNil(AssistantStateReducer.nextState(from: .idle, on: .beginExecuting))
        XCTAssertNil(AssistantStateReducer.nextState(from: .listening, on: .beginExecuting))
        XCTAssertNil(AssistantStateReducer.nextState(from: .thinking, on: .succeeded))
        XCTAssertNil(AssistantStateReducer.nextState(from: .success, on: .userBeganInput))
        XCTAssertNil(AssistantStateReducer.nextState(from: .error, on: .userBeganInput))
        XCTAssertNil(AssistantStateReducer.nextState(from: .working, on: .userBeganInput))
    }
}

final class AssistantStateMachineTests: XCTestCase {
    func testSendAppliesValidTransitionAndRecordsHistory() {
        let machine = AssistantStateMachine()

        let result = machine.send(.userBeganInput, reason: "user opened chat", taskID: "task-1")

        XCTAssertEqual(try? result.get(), .listening)
        XCTAssertEqual(machine.state, .listening)
        XCTAssertEqual(machine.history.count, 1)

        let recorded = machine.history[0]
        XCTAssertEqual(recorded.from, .idle)
        XCTAssertEqual(recorded.to, .listening)
        XCTAssertEqual(recorded.reason, "user opened chat")
        XCTAssertEqual(recorded.taskID, "task-1")
    }

    func testSendRejectsInvalidTransitionAndLeavesStateUnchanged() {
        let machine = AssistantStateMachine()

        let result = machine.send(.succeeded, reason: "should not apply")

        switch result {
        case .success:
            XCTFail("Expected invalid transition to fail")
        case .failure(let error):
            XCTAssertEqual(error, .invalidTransition(from: .idle, event: .succeeded))
        }

        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(machine.history.isEmpty)
    }

    func testActiveTaskIDClearsOnReturnToIdle() {
        let machine = AssistantStateMachine()
        machine.send(.userBeganInput, reason: "start", taskID: "task-42")
        machine.send(.beginInterpreting, reason: "interpret")
        machine.send(.beginExecuting, reason: "execute")
        XCTAssertEqual(machine.activeTaskID, "task-42")

        machine.send(.succeeded, reason: "done")
        machine.send(.acknowledge, reason: "user dismissed")

        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.activeTaskID)
        XCTAssertEqual(machine.history.count, 5)
    }
}
