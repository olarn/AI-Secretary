import Foundation

public struct DismissCandidate: Equatable, Sendable {
    public let id: UUID
    public let holdsKeyboard: Bool
    public let hasDismissable: Bool
    public let isCharacterVisible: Bool

    public init(
        id: UUID,
        holdsKeyboard: Bool,
        hasDismissable: Bool,
        isCharacterVisible: Bool = false
    ) {
        self.id = id
        self.holdsKeyboard = holdsKeyboard
        self.hasDismissable = hasDismissable
        self.isCharacterVisible = isCharacterVisible
    }
}

public func hasSomethingToDismiss(isChatVisible: Bool, visiblePanes: Int) -> Bool {
    isChatVisible || visiblePanes > 0
}

public enum DismissTrigger: Equatable, Sendable {
    case hotKey
    case ownWindow
}

public enum DismissStep: Equatable, Sendable {
    case dismissWindow
    case hideCharacter
}

public struct DismissDecision: Equatable, Sendable {
    public let id: UUID
    public let step: DismissStep

    public init(id: UUID, step: DismissStep) {
        self.id = id
        self.step = step
    }
}

public func dismissDecision(
    _ candidates: [DismissCandidate],
    trigger: DismissTrigger = .hotKey
) -> DismissDecision? {
    let dismissable = candidates.filter(\.hasDismissable)

    if trigger == .ownWindow {
        guard dismissable.isEmpty else { return nil }
        return candidates
            .first { $0.holdsKeyboard && $0.isCharacterVisible }
            .map { DismissDecision(id: $0.id, step: .hideCharacter) }
    }

    let chosen = dismissable.first(where: \.holdsKeyboard) ?? dismissable.first
    return chosen.map { DismissDecision(id: $0.id, step: .dismissWindow) }
}
