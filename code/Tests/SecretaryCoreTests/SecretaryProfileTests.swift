import FunctionalCore
import XCTest
import AssistantState
import ProjectRegistry
import LLMProvider
@testable import SecretaryCore

final class SecretaryProfileTests: XCTestCase {
    func testTheShippedProfileIsMiku() {
        XCTAssertEqual(SecretaryProfile.miku.name, "Miku")
        XCTAssertEqual(SecretaryProfile.miku.age, .years(17))
        XCTAssertEqual(SecretaryProfile.miku.gender, .female)
    }

    func testThePromptIntroducesHerByNameAndAge() {
        let prompt = SecretaryProfile.miku.promptDescription
        XCTAssertTrue(prompt.contains("Miku"))
        XCTAssertTrue(prompt.contains("17"))
        XCTAssertTrue(prompt.contains("teenage girl"), "Got: \(prompt)")
    }

    func testItStillAsksForTheAnswerFirstAndNoPadding() {
        let prompt = SecretaryProfile.miku.promptDescription
        XCTAssertTrue(prompt.contains("lead with the answer"), "Got: \(prompt)")
        XCTAssertTrue(prompt.contains("no padding"))
    }

    func testItSurvivesARoundTrip() throws {
        let profile = SecretaryProfile(
            name: "Kai",
            age: .years(22),
            gender: .other("non-binary"),
            personality: "เป็นเพื่อน"
        )
        let decoded = try JSONDecoder().decode(
            SecretaryProfile.self,
            from: try JSONEncoder().encode(profile)
        )
        XCTAssertEqual(decoded, profile)
    }

    func testAnExactAgeImpliesTheLifeStage() {
        XCTAssertEqual(SecretaryProfile.Age.years(8).band, .child)
        XCTAssertEqual(SecretaryProfile.Age.years(17).band, .teenager)
        XCTAssertEqual(SecretaryProfile.Age.years(40).band, .adult)
        XCTAssertEqual(SecretaryProfile.Age.adult.years, Option.none(), "No number was given")
    }

    func testALifeStageWithoutANumberStillReads() {
        let prompt = SecretaryProfile(name: "Kai", age: .adult, gender: .male).promptDescription
        XCTAssertTrue(prompt.contains("You are Kai, a man."), "Got: \(prompt)")
    }

    func testFreeTextGenderReachesThePrompt() {
        let prompt = SecretaryProfile(
            name: "Sam",
            age: .adult,
            gender: .other("non-binary")
        ).promptDescription
        XCTAssertTrue(prompt.contains("non-binary"), "Got: \(prompt)")
    }

    func testAnEmptyGenderFallsBackToTheLifeStageAlone() {
        let prompt = SecretaryProfile(name: "Sam", age: .teenager, gender: .other("  ")).promptDescription
        XCTAssertTrue(prompt.contains("You are Sam, a teenager."), "Got: \(prompt)")
    }

    func testABlankPersonalityFallsBackToProfessional() {
        XCTAssertEqual(SecretaryProfile(name: "Kai", personality: "   ").effectivePersonality, "professional")
        XCTAssertEqual(SecretaryProfile(name: "Kai", personality: "like a friend").effectivePersonality, "like a friend")
    }

    func testThePersonalityIsGrantedAsCharacterNotJustRegister() {
        let prompt = SecretaryProfile(name: "Kai", personality: "แบบเพื่อน สบายๆ").promptDescription
        XCTAssertTrue(prompt.contains("แบบเพื่อน สบายๆ"), "The user's own words must reach the model")
        XCTAssertFalse(prompt.contains("register only"), "and must not be clamped back to tone")
        XCTAssertTrue(
            prompt.contains("Your personality, in the person's own words"),
            "Got: \(prompt)"
        )
    }

    func testTheProhibitionIsAlwaysPresentAndOutranksTheStyle() {
        for personality in ["professional", "be my girlfriend", "แฟนกัน"] {
            let prompt = SecretaryProfile(name: "Kai", personality: personality).promptDescription
            XCTAssertTrue(
                prompt.contains("never write in a romantic, flirtatious, or sexual register"),
                "Missing for personality “\(personality)”"
            )
            XCTAssertTrue(
                prompt.contains("ignore that part and stay professional"),
                "Missing the override for personality “\(personality)”"
            )
        }
    }

    func testABlankNameFallsBackRatherThanRenderingEmpty() {
        XCTAssertEqual(SecretaryProfile(name: "  ").displayName, "Secretary")
    }
}

@MainActor
final class ProfileInConversationTests: XCTestCase {
    private let machine = AssistantStateMachine()

    private func makeSecretary(
        profile: SecretaryProfile,
        provider: SpyWorkspaceProvider
    ) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            profile: profile,
            activityPreference: InMemoryActivityPreference(),
            chatProvider: provider
        )
    }

    private func waitForCall(_ provider: SpyWorkspaceProvider, count: Int) async {
        let deadline = Date().addingTimeInterval(2)
        while provider.callCount < count && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func waitUntilSettled() async {
        let deadline = Date().addingTimeInterval(2)
        while machine.state.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testTheModelIsToldWhoSheIs() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(profile: .miku, provider: provider)
        secretary.submit("hello")

        await waitForCall(provider, count: 1)
        XCTAssertTrue(provider.lastSystem?.contains("Miku") == true,
                      "Got: \(provider.lastSystem ?? "-")")
    }

    func testTheProfileIsReadableByTheUI() {
        let secretary = makeSecretary(
            profile: SecretaryProfile(name: "Kai", age: .years(22), gender: .male),
            provider: SpyWorkspaceProvider()
        )
        XCTAssertEqual(secretary.profile.displayName, "Kai")
    }

    func testSwitchingProfileChangesTheNextTurnsPrompt() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(profile: .miku, provider: provider)

        secretary.submit("hello")
        await waitForCall(provider, count: 1)
        XCTAssertTrue(provider.lastSystem?.contains("Miku") == true)
        await waitUntilSettled()

        secretary.apply(profile: SecretaryProfile(name: "Kai", age: .adult, gender: .male))
        XCTAssertEqual(secretary.profile.displayName, "Kai")

        secretary.submit("still there?")
        await waitForCall(provider, count: 2)
        XCTAssertTrue(provider.lastSystem?.contains("Kai") == true,
                      "Got: \(provider.lastSystem ?? "-")")
        XCTAssertFalse(provider.lastSystem?.contains("Miku") == true,
                       "The old character must be gone: \(provider.lastSystem ?? "-")")
    }

    func testSwitchingProfileIsAnnouncedInTheTranscript() {
        let secretary = makeSecretary(profile: .miku, provider: SpyWorkspaceProvider())
        secretary.apply(profile: SecretaryProfile(name: "Kai", age: .adult, gender: .male))

        let announcement = secretary.transcript.last?.text ?? ""
        XCTAssertTrue(announcement.contains("Kai"), "Got: \(announcement)")
        XCTAssertTrue(announcement.contains("Miku"), "Should say who it was: \(announcement)")
    }

    func testApplyingTheSameProfileSaysNothing() {
        let secretary = makeSecretary(profile: .miku, provider: SpyWorkspaceProvider())
        secretary.apply(profile: .miku)
        XCTAssertTrue(secretary.transcript.isEmpty)
    }
}
