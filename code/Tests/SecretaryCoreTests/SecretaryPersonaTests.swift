import XCTest
import AssistantState
import ProjectRegistry
import LLMProvider
@testable import SecretaryCore

final class SecretaryPersonaTests: XCTestCase {
    func testTheShippedPersonaIsMiku() {
        XCTAssertEqual(SecretaryPersona.miku.name, "Miku")
        XCTAssertEqual(SecretaryPersona.miku.age, 17)
        XCTAssertEqual(SecretaryPersona.miku.gender, .female)
    }

    func testThePromptIntroducesHerByNameAndAge() {
        let prompt = SecretaryPersona.miku.promptDescription
        XCTAssertTrue(prompt.contains("Miku"))
        XCTAssertTrue(prompt.contains("17"))
        XCTAssertTrue(prompt.contains("young woman"))
    }

    /// Personality must not undo the instruction that makes answers usable.
    func testItStillAsksForTheAnswerFirstAndNoPadding() {
        let prompt = SecretaryPersona.miku.promptDescription
        XCTAssertTrue(prompt.contains("lead with the answer"), "Got: \(prompt)")
        XCTAssertTrue(prompt.contains("no padding"))
    }

    func testAPersonaWithoutAnAgeOrGenderStillReads() {
        let prompt = SecretaryPersona(name: "Kai").promptDescription
        XCTAssertTrue(prompt.contains("You are Kai."), "Got: \(prompt)")
        XCTAssertFalse(prompt.contains("young"))
    }

    /// It'll be persisted once the user can pick their own.
    func testItSurvivesARoundTrip() throws {
        let persona = SecretaryPersona(name: "Kai", age: 22, gender: .male)
        let decoded = try JSONDecoder().decode(
            SecretaryPersona.self,
            from: try JSONEncoder().encode(persona)
        )
        XCTAssertEqual(decoded, persona)
    }
}

@MainActor
final class PersonaInConversationTests: XCTestCase {
    private func makeSecretary(
        persona: SecretaryPersona,
        provider: SpyWorkspaceProvider
    ) -> Secretary {
        Secretary(
            stateMachine: AssistantStateMachine(),
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            persona: persona,
            activityPreference: InMemoryActivityPreference(),
            chatProvider: provider
        )
    }

    func testTheModelIsToldWhoSheIs() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(persona: .miku, provider: provider)
        secretary.submit("hello")

        let deadline = Date().addingTimeInterval(2)
        while provider.callCount == 0 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(provider.lastSystem?.contains("Miku") == true,
                      "Got: \(provider.lastSystem ?? "-")")
    }

    /// The name is what the panel labels her replies with.
    func testThePersonaIsReadableByTheUI() {
        let secretary = makeSecretary(
            persona: SecretaryPersona(name: "Kai", age: 22, gender: .male),
            provider: SpyWorkspaceProvider()
        )
        XCTAssertEqual(secretary.persona.name, "Kai")
    }
}
