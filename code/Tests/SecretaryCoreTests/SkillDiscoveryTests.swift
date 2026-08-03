import XCTest
@testable import SecretaryCore

final class SkillDiscoveryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillDiscoveryTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func writeSkill(
        named folder: String,
        under base: URL,
        frontmatter: String?
    ) {
        let dir = base.appendingPathComponent(folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = frontmatter.map { "---\n\($0)\n---\n\nBody text." } ?? "Body text with no frontmatter."
        try? body.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    func testReadsNameAndDescriptionFromFrontmatter() {
        let home = tempRoot.appendingPathComponent("home")
        writeSkill(
            named: "grilling",
            under: home.appendingPathComponent(".claude/skills"),
            frontmatter: "name: grilling\ndescription: Grill the user relentlessly."
        )

        let found = SkillDiscovery.discover(projectPaths: [], homeDirectory: home)

        XCTAssertEqual(found, [
            SkillInfo(id: "grilling", name: "grilling", summary: "Grill the user relentlessly.", scope: .user)
        ])
    }

    func testFallsBackToFolderNameWhenFrontmatterIsMissing() {
        let home = tempRoot.appendingPathComponent("home")
        writeSkill(named: "mystery-skill", under: home.appendingPathComponent(".claude/skills"), frontmatter: nil)

        let found = SkillDiscovery.discover(projectPaths: [], homeDirectory: home)

        XCTAssertEqual(found, [
            SkillInfo(id: "mystery-skill", name: "mystery-skill", summary: "", scope: .user)
        ])
    }

    func testMissingDirectoryYieldsNoEntriesRatherThanFailing() {
        let home = tempRoot.appendingPathComponent("no-such-home")

        XCTAssertEqual(SkillDiscovery.discover(projectPaths: [], homeDirectory: home), [])
    }

    func testCombinesUserSkillsWithEachProjectsSkills() {
        let home = tempRoot.appendingPathComponent("home")
        writeSkill(named: "shared", under: home.appendingPathComponent(".claude/skills"), frontmatter: "name: Shared\ndescription: user-scoped")

        let project = tempRoot.appendingPathComponent("MyProject")
        writeSkill(named: "local-only", under: project.appendingPathComponent(".claude/skills"), frontmatter: "name: Local Only\ndescription: project-scoped")

        let found = SkillDiscovery.discover(projectPaths: [project.path], homeDirectory: home)

        XCTAssertEqual(Set(found.map(\.id)), ["shared", "local-only"])
        XCTAssertEqual(found.first { $0.id == "shared" }?.scope, .user)
        XCTAssertEqual(found.first { $0.id == "local-only" }?.scope, .project)
    }

    func testSkipsFilesThatAreNotDirectories() {
        let skillsDir = tempRoot.appendingPathComponent("home/.claude/skills")
        try? FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try? "not a skill".write(to: skillsDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let found = SkillDiscovery.discover(projectPaths: [], homeDirectory: tempRoot.appendingPathComponent("home"))

        XCTAssertEqual(found, [])
    }
}
