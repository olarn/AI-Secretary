import FunctionalCore
import Foundation
import Observation
import os

/// Owns the current `AssistantState` and the audit trail of transitions.
///
/// **Never set `state` from outside — submit an event.** A direct write skips
/// the transition table, the history entry and the log line all at once.
///
/// The decision itself lives in `decideTransition`; this type only holds the
/// result and logs it, so the transition table stays testable without an object.
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
        // A task survives until the machine comes to rest; an explicit taskID
        // on this event always wins.
        activeTaskID = taskID.orElse(next == .idle ? Option.none() : activeTaskID)
        history.append(transition)

        logger.info(
            "Transition \(transition.from.description, privacy: .public) -> \(transition.to.description, privacy: .public) (\(transition.reason, privacy: .public))"
        )
    }
}
