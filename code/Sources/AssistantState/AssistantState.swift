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

    /// Whether a request is in flight — something is being worked out or done,
    /// and a new message arriving now has to be decided about rather than just
    /// run.
    ///
    /// `listening` is not busy: it means the person is typing, which is exactly
    /// when the next message is being written.
    public var isBusy: Bool {
        switch self {
        case .thinking, .working: true
        case .idle, .listening, .success, .error: false
        }
    }
}

/// The state worth saying out loud, or nothing when there is none.
///
/// Idle is the answer most of the time, and "IDLE" printed under a character
/// standing on the desktop is a label that never varies and so never tells you
/// anything. The states that mean something are the ones that don't last.
public func characterStatusTag(for state: AssistantState) -> String? {
    state == .idle ? nil : state.description.uppercased()
}

/// What to call the character on screen.
///
/// One rule in one place because it is shown twice — under the character on the
/// desktop and at the top of the chat — and two copies would drift the first
/// time a state was added.
public func characterStatusLabel(name: String, state: AssistantState) -> String {
    characterStatusTag(for: state).map { "\(name) - \($0)" } ?? name
}

/// Events that can drive a state transition.
///
/// Deliberately carries no UI or tool detail — the caller attaches
/// reason/taskID/toolStatus when submitting, which is what keeps this enum
/// usable from both the app and the tests.
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

/// The transition table.
///
/// Kept free of side effects and of any UI dependency so the state machine can
/// be tested on its own. Absence is `Option.none`, so "this event does nothing
/// in this state" is a value the caller must handle rather than a `nil` that
/// reads as an oversight.
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
