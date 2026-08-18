import FunctionalCore
import Foundation
import LLMProvider

/// Which model and effort a character answers with, when she has been told.
///
/// `.none()` on either half means "whatever Claude Code is configured to use" —
/// an absence, not a value, which is why both are `Option` rather than a
/// sentinel model called "default".
public struct AssistantChoice: Equatable, Sendable {
    public let model: Option<ChatModel>
    public let effort: Option<Effort>

    public static let inherited = AssistantChoice(model: .none(), effort: .none())

    public init(model: Option<ChatModel>, effort: Option<Effort>) {
        self.model = model
        self.effort = effort
    }
}

/// Where a character's model and effort survive between launches.
///
/// They did not, until now. `selectModel` set a property and said a line, and
/// nothing wrote it anywhere — so every character came back on "Default" every
/// morning, and the only way to notice was to read the badge. Sprint 12 recorded
/// the omission deliberately ("Model กับ Effort … ไม่ใช่ field ของ profile ที่เก็บลงดิสก์")
/// because those rows apply immediately rather than waiting for Save; remembering
/// them does not require giving that up, which is why this is its own store and
/// not a pair of profile fields.
public protocol AssistantChoiceStoring: Sendable {
    func load() -> AssistantChoice
    func save(_ choice: AssistantChoice)
}

/// The default, and it deliberately reaches nowhere — the same rule the grant
/// store follows. A suite that forgot to override it would otherwise write into
/// the person's own preferences.
public struct InMemoryAssistantChoiceStore: AssistantChoiceStoring {
    public init() {}
    public func load() -> AssistantChoice { .inherited }
    public func save(_ choice: AssistantChoice) {}
}

/// Per character, written the moment the choice is made.
///
/// Its own key namespace rather than the appearance one: Sprint 12 sorted these
/// rows by what they are about, and "who is answering" is not "how the app
/// looks". Sharing a namespace would only be convenient.
public final class UserDefaultsAssistantChoiceStore: AssistantChoiceStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let character: UUID

    public init(defaults: UserDefaults = .standard, character: UUID) {
        self.defaults = defaults
        self.character = character
    }

    private var modelKey: String { "assistant.\(character.uuidString).model" }
    private var effortKey: String { "assistant.\(character.uuidString).effort" }

    /// **An unrecognised value reads as "inherit", never as a crash and never as
    /// a guess.** Model ids come and go between Claude Code releases, so a
    /// character configured for a model that no longer exists has to fall back to
    /// whatever the CLI is set to rather than insisting on a name nothing will
    /// answer to.
    public func load() -> AssistantChoice {
        AssistantChoice(
            model: Option.fromOptional(defaults.string(forKey: modelKey))
                .flatMap { id in Option.fromOptional(ChatModel.known.first { $0.id == id }) }^,
            effort: Option.fromOptional(defaults.string(forKey: effortKey))
                .flatMap { raw in Option.fromOptional(Effort(rawValue: raw)) }^
        )
    }

    /// Going back to "Default" is a choice too, so it is written as the absence
    /// of a key rather than left alone — otherwise clearing it would come back
    /// the next morning.
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
