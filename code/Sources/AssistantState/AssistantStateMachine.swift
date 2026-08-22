import FunctionalCore
import Foundation
import Observation
import os

@Observable
public final class AssistantStateMachine {
    public private(set) var state: AssistantState
    public private(set) var history: [StateTransition] = []
    public private(set) var activeTaskID: Option<String> = .none()

    private let logger = Logger(subsystem: "com.aisecretary.app", category: "AssistantStateMachine")

    public init(initialState: AssistantState = .idle) {
        self.state = initialState
    }

    @discardableResult
    public func send(
        _ event: AssistantEvent,
        reason: String,
        taskID: Option<String> = .none(),
        toolStatus: Option<String> = .none()
    ) -> Either<TransitionError, AssistantState> {
        decideTransition(from: state, on: event)
            .bimap(
                { failure in
                    self.logger.error("Rejected transition: \(String(describing: failure), privacy: .public)")
                    return failure
                },
                { next in
                    self.apply(event, to: next, reason: reason, taskID: taskID, toolStatus: toolStatus)
                    return next
                }
            )^
    }

    private func apply(
        _ event: AssistantEvent,
        to next: AssistantState,
        reason: String,
        taskID: Option<String>,
        toolStatus: Option<String>
    ) {
        let transition = StateTransition(
            from: state,
            to: next,
            event: event,
            reason: reason,
            taskID: taskID.orElse(activeTaskID),
            toolStatus: toolStatus
        )

        state = next
        activeTaskID = taskIDSurvivingTransition(
            explicit: taskID, arrivingAt: next, current: activeTaskID
        )
        history.append(transition)

        logger.info(
            "Transition \(transition.from.description, privacy: .public) -> \(transition.to.description, privacy: .public) (\(transition.reason, privacy: .public))"
        )
    }
}
