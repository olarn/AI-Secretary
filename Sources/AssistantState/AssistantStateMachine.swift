import Foundation
import Observation
import os

/// Owns the current `AssistantState` and the audit trail of transitions.
/// UI layers observe this; they never mutate `state` directly, only submit
/// events through `send(_:reason:taskID:toolStatus:)`.
@Observable
public final class AssistantStateMachine {
    public private(set) var state: AssistantState
    public private(set) var history: [StateTransition] = []
    public private(set) var activeTaskID: String?

    private let logger = Logger(subsystem: "com.aisecretary.app", category: "AssistantStateMachine")

    public init(initialState: AssistantState = .idle) {
        self.state = initialState
    }

    @discardableResult
    public func send(
        _ event: AssistantEvent,
        reason: String,
        taskID: String? = nil,
        toolStatus: String? = nil
    ) -> Result<AssistantState, TransitionError> {
        guard let next = AssistantStateReducer.nextState(from: state, on: event) else {
            let failure = TransitionError.invalidTransition(from: state, event: event)
            logger.error("Rejected transition: \(String(describing: failure), privacy: .public)")
            return .failure(failure)
        }

        let transition = StateTransition(
            from: state,
            to: next,
            event: event,
            reason: reason,
            taskID: taskID ?? activeTaskID,
            toolStatus: toolStatus
        )

        state = next
        activeTaskID = taskID ?? (next == .idle ? nil : activeTaskID)
        history.append(transition)

        logger.info(
            "Transition \(transition.from.description, privacy: .public) -> \(transition.to.description, privacy: .public) (\(transition.reason, privacy: .public))"
        )

        return .success(next)
    }
}
