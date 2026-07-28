import FunctionalCore
import Foundation

/// The assistant's lifecycle state, shared between UI and orchestration logic.
///
/// IDLE -> LISTENING -> THINKING -> WORKING -> SUCCESS | ERROR -> IDLE
public enum AssistantState: String, Equatable, Sendable, CustomStringConvertible {
    case idle
    case listening
    case thinking
    case working
    case success
    case error

    public var description: String { rawValue }
}

/// Events that can drive a state transition. Carries no UI or tool details;
/// callers attach a reason/taskID/toolStatus when submitting the event.
public enum AssistantEvent: Equatable, Sendable {
    case userBeganInput
    case beginInterpreting
    case beginExecuting
    case succeeded
    case failed
    case acknowledge
}

/// A single recorded transition, per CLAUDE.md's requirement to track
/// reason, timestamp, active task, and tool execution status.
public struct StateTransition: Equatable, Sendable {
    public let from: AssistantState
    public let to: AssistantState
    public let event: AssistantEvent
    public let reason: String
    public let timestamp: Date
    public let taskID: Option<String>
    public let toolStatus: Option<String>

    public init(
        from: AssistantState,
        to: AssistantState,
        event: AssistantEvent,
        reason: String,
        timestamp: Date = Date(),
        taskID: Option<String> = .none(),
        toolStatus: Option<String> = .none()
    ) {
        self.from = from
        self.to = to
        self.event = event
        self.reason = reason
        self.timestamp = timestamp
        self.taskID = taskID
        self.toolStatus = toolStatus
    }
}

public enum TransitionError: Error, Equatable, Sendable {
    case invalidTransition(from: AssistantState, event: AssistantEvent)
}

/// Pure transition table. No side effects, no UI dependency — this is what
/// makes the state machine independently unit-testable.
///
/// Absence is `Option.none`, so "this event does nothing in this state" is a
/// value the caller must handle rather than a `nil` that reads as an oversight.
public func nextAssistantState(
    from state: AssistantState,
    on event: AssistantEvent
) -> Option<AssistantState> {
    switch (state, event) {
    case (.idle, .userBeganInput):
        return .some(.listening)
    case (.listening, .beginInterpreting):
        return .some(.thinking)
    case (.thinking, .beginExecuting):
        return .some(.working)
    case (.working, .succeeded):
        return .some(.success)
    case (.working, .failed):
        return .some(.error)
    case (.success, .acknowledge):
        return .some(.idle)
    case (.error, .acknowledge):
        return .some(.idle)
    default:
        return .none()
    }
}

/// The transition as a decision: the rejected rail carries why, so a caller can
/// log or surface it without reconstructing the reason.
public func decideTransition(
    from state: AssistantState,
    on event: AssistantEvent
) -> Either<TransitionError, AssistantState> {
    nextAssistantState(from: state, on: event)
        .fold(
            { .left(.invalidTransition(from: state, event: event)) },
            { .right($0) }
        )
}
