import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

final class AssistantChoiceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let character = UUID()

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AssistantChoiceStoreTests-\(UUID().uuidString)")
    }

    private func makeStore() -> UserDefaultsAssistantChoiceStore {
        UserDefaultsAssistantChoiceStore(defaults: defaults, character: character)
    }

    func testNothingChosenReadsAsInherited() {
        XCTAssertEqual(makeStore().load(), .inherited)
    }

    func testAChoiceSurvivesBeingReadBackByAFreshStore() {
        makeStore().save(AssistantChoice(model: .some(.sonnet5), effort: .some(.high)))

        let reloaded = makeStore().load()
        XCTAssertEqual(reloaded.model.toOptional(), .sonnet5)
        XCTAssertEqual(reloaded.effort.toOptional(), .high)
    }

    func testClearingItIsRemembered() {
        let store = makeStore()
        store.save(AssistantChoice(model: .some(.sonnet5), effort: .some(.high)))
        store.save(.inherited)

        XCTAssertEqual(makeStore().load(), .inherited)
    }

    func testAModelThatNoLongerExistsReadsAsInherited() {
        defaults.set("claude-from-a-future-that-never-came", forKey: "assistant.\(character.uuidString).model")
        defaults.set("nonsense", forKey: "assistant.\(character.uuidString).effort")

        XCTAssertEqual(makeStore().load(), .inherited)
    }

    func testEachCharacterKeepsHerOwn() {
        let her = UserDefaultsAssistantChoiceStore(defaults: defaults, character: character)
        let him = UserDefaultsAssistantChoiceStore(defaults: defaults, character: UUID())

        her.save(AssistantChoice(model: .some(.sonnet5), effort: .none()))

        XCTAssertEqual(her.load().model.toOptional(), .sonnet5)
        XCTAssertEqual(him.load(), .inherited, "One character's choice is not everybody's")
    }
}

@MainActor
final class SecretaryRemembersItsModelTests: XCTestCase {
    private final class Spy: AssistantChoiceStoring, @unchecked Sendable {
        var stored: AssistantChoice = .inherited
        func load() -> AssistantChoice { stored }
        func save(_ choice: AssistantChoice) { stored = choice }
    }

    private func makeSecretary(_ store: AssistantChoiceStoring) -> Secretary {
        Secretary(
            stateMachine: AssistantStateMachine(),
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            chatProvider: FakeChatProvider(.events([.completed(stopReason: .none(), usage: .none())])),
            choiceStore: store
        )
    }

    func testChoosingAModelWritesItDown() {
        let store = Spy()
        makeSecretary(store).selectModel(.some(.sonnet5))

        XCTAssertEqual(store.stored.model.toOptional(), .sonnet5)
    }

    func testChoosingAnEffortKeepsTheModelItWasAlreadyOn() {
        let store = Spy()
        let secretary = makeSecretary(store)
        secretary.selectModel(.some(.sonnet5))
        secretary.selectEffort(.some(.high))

        XCTAssertEqual(store.stored.model.toOptional(), .sonnet5, "Writing one half must not drop the other")
        XCTAssertEqual(store.stored.effort.toOptional(), .high)
    }

    func testANewSecretaryStartsOnWhatWasChosenBefore() {
        let store = Spy()
        makeSecretary(store).selectModel(.some(.sonnet5))

        let afterRestart = makeSecretary(store)
        XCTAssertEqual(afterRestart.model.toOptional(), .sonnet5)
        XCTAssertEqual(afterRestart.modelBadgeText, "Sonnet 5 | Default")
    }

    func testWithNothingRememberedSheInheritsAsBefore() {
        XCTAssertFalse(makeSecretary(Spy()).model.isDefined)
    }
}
