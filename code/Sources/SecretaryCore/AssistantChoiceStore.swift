import FunctionalCore
import Foundation
import LLMProvider

public struct AssistantChoice: Equatable, Sendable {
    public let model: Option<ChatModel>
    public let effort: Option<Effort>

    public static let inherited = AssistantChoice(model: .none(), effort: .none())

    public init(model: Option<ChatModel>, effort: Option<Effort>) {
        self.model = model
        self.effort = effort
    }
}

public protocol AssistantChoiceStoring: Sendable {
    func load() -> AssistantChoice
    func save(_ choice: AssistantChoice)
}

public struct InMemoryAssistantChoiceStore: AssistantChoiceStoring {
    public init() {}
    public func load() -> AssistantChoice { .inherited }
    public func save(_ choice: AssistantChoice) {}
}

public final class UserDefaultsAssistantChoiceStore: AssistantChoiceStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let character: UUID

    public init(defaults: UserDefaults = .standard, character: UUID) {
        self.defaults = defaults
        self.character = character
    }

    private var modelKey: String { "assistant.\(character.uuidString).model" }
    private var effortKey: String { "assistant.\(character.uuidString).effort" }

    public func load() -> AssistantChoice {
        AssistantChoice(
            model: Option.fromOptional(defaults.string(forKey: modelKey))
                .flatMap { id in Option.fromOptional(ChatModel.known.first { $0.id == id }) }^,
            effort: Option.fromOptional(defaults.string(forKey: effortKey))
                .flatMap { raw in Option.fromOptional(Effort(rawValue: raw)) }^
        )
    }

    public func save(_ choice: AssistantChoice) {
        choice.model.fold(
            { defaults.removeObject(forKey: modelKey) },
            { defaults.set($0.id, forKey: modelKey) }
        )
        choice.effort.fold(
            { defaults.removeObject(forKey: effortKey) },
            { defaults.set($0.rawValue, forKey: effortKey) }
        )
    }
}
