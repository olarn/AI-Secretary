import FunctionalCore
import Foundation

public enum AssistantState: String, Equatable, Sendable, CustomStringConvertible {
    case idle
    case listening
    case thinking
    case working
    case success
    case error

    public var description: String { rawValue }

    public var isBusy: Bool {
        switch self {
        case .thinking, .working: true
        case .idle, .listening, .success, .error: false
        }
    }

    public var isWorthAnnouncing: Bool { self != .idle }

    public var isAtRest: Bool { self == .idle }
}

public func taskIDSurvivingTransition(
    explicit: Option<String>,
    arrivingAt next: AssistantState,
    current: Option<String>
) -> Option<String> {
    explicit.orElse(next.isAtRest ? Option.none() : current)
}

public func characterStatusTag(for state: AssistantState) -> String? {
    state.isWorthAnnouncing ? state.description.uppercased() : nil
}

public func characterStatusLabel(name: String, state: AssistantState) -> String {
    characterStatusTag(for: state).map { "\(name) - \($0)" } ?? name
}

public enum AssistantEvent: Equatable, Sendable {
    case userBeganInput
    case beginInterpreting
    case beginExecuting
    case succeeded
    case failed
    case acknowledge
}

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
