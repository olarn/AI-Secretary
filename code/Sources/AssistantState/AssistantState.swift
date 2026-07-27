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
    public let taskID: String?
    public let toolStatus: String?

    public init(
        from: AssistantState,
        to: AssistantState,
        event: AssistantEvent,
        reason: String,
        timestamp: Date = Date(),
        taskID: String? = nil,
        toolStatus: String? = nil
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

public enum TransitionError: Error, Equatable {
    case invalidTransition(from: AssistantState, event: AssistantEvent)
}

/// Pure transition table. No side effects, no UI dependency — this is what
/// makes the state machine independently unit-testable.
public enum AssistantStateReducer {
    public static func nextState(from state: AssistantState, on event: AssistantEvent) -> AssistantState? {
        switch (state, event) {
        case (.idle, .userBeganInput):
            return .listening
        case (.listening, .beginInterpreting):
            return .thinking
        case (.thinking, .beginExecuting):
            return .working
        case (.working, .succeeded):
            return .success
        case (.working, .failed):
            return .error
        case (.success, .acknowledge):
            return .idle
        case (.error, .acknowledge):
            return .idle
        default:
            return nil
        }
    }
}
