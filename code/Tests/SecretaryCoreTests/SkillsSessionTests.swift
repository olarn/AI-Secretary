import FunctionalCore
import XCTest
import AssistantState
import ProjectRegistry
import ToolAdapters
@testable import SecretaryCore

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

        let grillingUninstalledBetweenTurns = [skills[1]]
        installed = grillingUninstalledBetweenTurns
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

    func testRegisteringAProjectBringsItsSkillsIntoTheList() {
        let registry = ProjectRegistry(store: InMemoryProjectStore())
        let projectSkill = SkillInfo(
            id: "swift-functional-programming",
            name: "swift-functional-programming",
            summary: "Bow, in this repo.",
            scope: .project
        )
        let secretary = Secretary(
            stateMachine: machine,
            registry: registry,
            adapter: SpyAdapter(),
            fileAdapter: SpyFileAdapter(),
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: provider,
            discoverSkills: { paths in paths.isEmpty ? self.skills : self.skills + [projectSkill] }
        )
        XCTAssertEqual(secretary.availableSkills, skills)

        _ = registry.add(Project(name: "AI Secretary", path: "/tmp/ai-secretary"))
        secretary.projectsDidChange()

        XCTAssertEqual(secretary.availableSkills, skills + [projectSkill])
    }

    func testTheListIsRescannedEvenWithoutAWorkspaceToRescope() {
        let registry = ProjectRegistry(store: InMemoryProjectStore())
        var installed = skills
        provider.hasWorkspaceTools = false
        let secretary = Secretary(
            stateMachine: machine,
            registry: registry,
            adapter: SpyAdapter(),
            fileAdapter: SpyFileAdapter(),
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: provider,
            discoverSkills: { _ in installed }
        )

        installed = [skills[1]]
        secretary.projectsDidChange()

        XCTAssertEqual(secretary.availableSkills, [skills[1]])
    }
}
