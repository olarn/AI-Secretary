import FunctionalCore
import XCTest
import AssistantState
import ProjectRegistry
import ToolAdapters
@testable import SecretaryCore

/// `toggleSkill`/`selectedSkills` are session-only, and the restriction they
/// produce is a soft hint in the system prompt — there is no CLI flag that
/// gates which skills a session can invoke.
@MainActor
final class SkillsSessionTests: XCTestCase {
    private var machine: AssistantStateMachine!
    private var provider: SpyWorkspaceProvider!

    private let skills = [
        SkillInfo(id: "grilling", name: "grilling", summary: "Grill the user.", scope: .user),
        SkillInfo(id: "brainstorming", name: "brainstorming", summary: "Explore intent.", scope: .user)
    ]

    override func setUp() {
        super.setUp()
        machine = AssistantStateMachine()
        provider = SpyWorkspaceProvider()
    }

    private func makeSecretary(projects: [Project] = [], discovered: [SkillInfo]? = nil) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: projects)),
            adapter: SpyAdapter(),
            fileAdapter: SpyFileAdapter(),
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: provider,
            discoverSkills: { _ in discovered ?? self.skills }
        )
    }

    private func waitUntilIdle(timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while machine.state != .idle && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testToggleSkillAddsAndRemovesFromSelection() {
        let secretary = makeSecretary()

        secretary.toggleSkill("grilling")
        XCTAssertEqual(secretary.selectedSkills, ["grilling"])

        secretary.toggleSkill("grilling")
        XCTAssertEqual(secretary.selectedSkills, [])
    }

    func testRefreshingDropsSelectionForASkillThatDisappeared() {
        var installed = skills
        let secretary = Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            adapter: SpyAdapter(),
            fileAdapter: SpyFileAdapter(),
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: provider,
            discoverSkills: { _ in installed }
        )
        secretary.toggleSkill("grilling")
        XCTAssertEqual(secretary.selectedSkills, ["grilling"])

        installed = [skills[1]] // "grilling" uninstalled between turns
        secretary.refreshAvailableSkills()

        XCTAssertEqual(secretary.selectedSkills, [], "A skill that disappeared must not stay selected")
        XCTAssertEqual(secretary.availableSkills, [skills[1]])
    }

    func testNoSkillsCheckedSaysNothingAboutSkills() async {
        let secretary = makeSecretary(projects: [
            Project(name: "Fixture", path: "/tmp/skills-fixture", allowedTools: [Secretary.claudeCodeToolID])
        ])

        secretary.submit("hello there")
        await waitUntilIdle()

        XCTAssertFalse(provider.lastSystem?.contains("picked these skills") ?? true)
    }

    /// Checking asks for a skill to be *preferred*. It used to ask for the
    /// others to be avoided, which is the opposite operation and is why a
    /// checked skill could sit there never being used.
    func testCheckedSkillsAreAskedForRatherThanTheOthersBanned() async {
        let secretary = makeSecretary(projects: [
            Project(name: "Fixture", path: "/tmp/skills-fixture", allowedTools: [Secretary.claudeCodeToolID])
        ])
        secretary.toggleSkill("grilling")

        secretary.submit("hello there")
        await waitUntilIdle()

        let system = provider.lastSystem ?? ""
        XCTAssertTrue(system.contains("Prefer them"), system)
        XCTAssertFalse(
            system.contains("Don't invoke any other"),
            "Checking must not turn into a ban on everything else"
        )
        XCTAssertTrue(system.contains("grilling"), system)
        XCTAssertFalse(system.contains("brainstorming"), "Unselected skills must not be named as chosen")
    }
}
