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

    // MARK: - Plugin skills

    private func writeSettings(enabledPlugins: [String: Bool], under claudeHome: URL) {
        try? FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        let pairs = enabledPlugins.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", ")
        let json = "{\"enabledPlugins\": {\(pairs)}}"
        try? json.write(to: claudeHome.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    }

    func testDiscoversSkillsFromAnEnabledPluginsCache() {
        let home = tempRoot.appendingPathComponent("home")
        let claudeHome = home.appendingPathComponent(".claude")
        writeSettings(enabledPlugins: ["superpowers@claude-plugins-official": true], under: claudeHome)
        writeSkill(
            named: "brainstorming",
            under: claudeHome.appendingPathComponent("plugins/cache/claude-plugins-official/superpowers/6.2.0/skills"),
            frontmatter: "name: brainstorming\ndescription: Explore intent before building."
        )

        let found = SkillDiscovery.discover(projectPaths: [], homeDirectory: home)

        XCTAssertEqual(found, [
            SkillInfo(
                id: "superpowers@claude-plugins-official:brainstorming",
                name: "superpowers:brainstorming",
                summary: "Explore intent before building.",
                scope: .plugin(id: "superpowers@claude-plugins-official")
            )
        ])
    }

    func testIgnoresDisabledPlugins() {
        let home = tempRoot.appendingPathComponent("home")
        let claudeHome = home.appendingPathComponent(".claude")
        writeSettings(enabledPlugins: ["superpowers@claude-plugins-official": false], under: claudeHome)
        writeSkill(
            named: "brainstorming",
            under: claudeHome.appendingPathComponent("plugins/cache/claude-plugins-official/superpowers/6.2.0/skills"),
            frontmatter: "name: brainstorming\ndescription: Explore intent before building."
        )

        XCTAssertEqual(SkillDiscovery.discover(projectPaths: [], homeDirectory: home), [])
    }

    func testFallsBackToTheMarketplaceRootForASinglePluginMarketplace() {
        let home = tempRoot.appendingPathComponent("home")
        let claudeHome = home.appendingPathComponent(".claude")
        writeSettings(enabledPlugins: ["fable@fable-method": true], under: claudeHome)
        // No plugins/cache entry at all — only the marketplace clone itself,
        // the layout a single-plugin marketplace actually uses.
        writeSkill(
            named: "fable-loop",
            under: claudeHome.appendingPathComponent("plugins/marketplaces/fable-method/skills"),
            frontmatter: "name: fable-loop\ndescription: Orchestrated end-to-end workflow."
        )

        let found = SkillDiscovery.discover(projectPaths: [], homeDirectory: home)

        XCTAssertEqual(found, [
            SkillInfo(
                id: "fable@fable-method:fable-loop",
                name: "fable:fable-loop",
                summary: "Orchestrated end-to-end workflow.",
                scope: .plugin(id: "fable@fable-method")
            )
        ])
    }

    func testDoesNotPullInOtherPluginsSharingTheSameMarketplace() {
        let home = tempRoot.appendingPathComponent("home")
        let claudeHome = home.appendingPathComponent(".claude")
        writeSettings(enabledPlugins: ["fable@fable-method": true], under: claudeHome)
        writeSkill(
            named: "fable-loop",
            under: claudeHome.appendingPathComponent("plugins/marketplaces/fable-method/skills"),
            frontmatter: "name: fable-loop\ndescription: Orchestrated workflow."
        )
        // A second, unrelated plugin hosted by the same marketplace, not
        // itself enabled — must not show up just because the marketplace
        // root was scanned as a fallback for "fable".
        writeSkill(
            named: "other-thing",
            under: claudeHome.appendingPathComponent("plugins/marketplaces/fable-method/plugins/unrelated-plugin/skills"),
            frontmatter: "name: other-thing\ndescription: Not enabled."
        )

        let found = SkillDiscovery.discover(projectPaths: [], homeDirectory: home)

        XCTAssertEqual(found.map(\.id), ["fable@fable-method:fable-loop"])
    }

    func testCombinesStandaloneAndPluginSkills() {
        let home = tempRoot.appendingPathComponent("home")
        let claudeHome = home.appendingPathComponent(".claude")
        writeSettings(enabledPlugins: ["superpowers@claude-plugins-official": true], under: claudeHome)
        writeSkill(named: "grilling", under: claudeHome.appendingPathComponent("skills"), frontmatter: "name: grilling\ndescription: Grill the user.")
        writeSkill(
            named: "brainstorming",
            under: claudeHome.appendingPathComponent("plugins/cache/claude-plugins-official/superpowers/6.2.0/skills"),
            frontmatter: "name: brainstorming\ndescription: Explore intent."
        )

        let found = SkillDiscovery.discover(projectPaths: [], homeDirectory: home)

        XCTAssertEqual(Set(found.map(\.id)), ["grilling", "superpowers@claude-plugins-official:brainstorming"])
    }

    func testNoSettingsFileYieldsNoPluginSkillsRatherThanFailing() {
        let home = tempRoot.appendingPathComponent("home")
        writeSkill(named: "grilling", under: home.appendingPathComponent(".claude/skills"), frontmatter: nil)

        // No .claude/settings.json written at all.
        let found = SkillDiscovery.discover(projectPaths: [], homeDirectory: home)

        XCTAssertEqual(found.map(\.id), ["grilling"])
    }
}

/// What the checked skills turn into in the prompt.
final class SkillsPromptTests: XCTestCase {
    private func skill(_ name: String, _ summary: String = "") -> SkillInfo {
        SkillInfo(id: name, name: name, summary: summary, scope: .user)
    }

    func testNothingCheckedSaysNothing() {
        XCTAssertEqual(skillsPrompt(for: []), "")
    }

    /// The description is the part the model can match a request against. The
    /// panel shows it; not passing it on left a bare name to guess from, which
    /// is why a checked skill could never come up.
    func testTheDescriptionTravelsWithTheName() {
        let prompt = skillsPrompt(for: [skill("grilling", "Use when cooking over fire")])
        XCTAssertTrue(prompt.contains("grilling"), prompt)
        XCTAssertTrue(prompt.contains("Use when cooking over fire"), prompt)
    }

    /// Checking asks for something, it does not forbid the rest — the opposite
    /// operation, and the one that made the checkbox feel broken.
    func testItAsksRatherThanForbids() {
        let prompt = skillsPrompt(for: [skill("grilling")])
        XCTAssertTrue(prompt.contains("Prefer them"), prompt)
        XCTAssertFalse(prompt.lowercased().contains("only use these"), prompt)
        XCTAssertTrue(prompt.contains("still there if none of these fit"), prompt)
    }

    func testASkillWithNoDescriptionIsStillListed() {
        let prompt = skillsPrompt(for: [skill("bare")])
        XCTAssertTrue(prompt.contains("- bare"), prompt)
        XCTAssertFalse(prompt.contains("bare —"), "no dangling dash where a description isn't")
    }

    /// Twenty checked skills must not become the largest thing in the request.
    func testALongDescriptionIsCutShort() {
        let long = String(repeating: "x", count: 400)
        let prompt = skillsPrompt(for: [skill("verbose", long)])
        XCTAssertTrue(prompt.contains("…"), prompt)
        XCTAssertFalse(prompt.contains(String(repeating: "x", count: maxSkillSummaryLength + 1)))
    }

    /// A description written over several lines would otherwise break the list
    /// into items that aren't skills.
    func testAMultiLineDescriptionStaysOnOneLine() {
        let prompt = skillsPrompt(for: [skill("wrapped", "first line\n  second line")])
        XCTAssertTrue(prompt.contains("first line second line"), prompt)
    }
}
