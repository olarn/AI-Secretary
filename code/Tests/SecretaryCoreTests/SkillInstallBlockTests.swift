import XCTest
import LLMProvider
@testable import SecretaryCore

/// Asking to install a skill, and the line between asking and merely saying so.
final class SkillInstallBlockTests: XCTestCase {
    func testAMessageWithNoBlockComesBackUntouched() {
        let text = "I could do that with the canva skill, but you don't have it."
        let parsed = SkillInstallBlock.parse(text)

        XCTAssertEqual(parsed.body, text)
        XCTAssertNil(parsed.plugin, "Talking about a skill is not asking for it")
    }

    func testTheBlockNamesThePluginAndLeavesTheProse() {
        let parsed = SkillInstallBlock.parse("""
        I need the Canva skill for this.

        ```install-skill
        canva
        ```
        """)

        XCTAssertEqual(parsed.plugin, "canva")
        XCTAssertEqual(parsed.body, "I need the Canva skill for this.")
    }

    /// The lesson the choices block paid for: a block left in the text renders
    /// as raw markdown underneath the thing it was supposed to become.
    func testTheBlockNeverReachesTheScreen() {
        let parsed = SkillInstallBlock.parse("Before\n```install-skill\ncanva\n```\nAfter")

        XCTAssertFalse(parsed.body.contains("install-skill"))
        XCTAssertFalse(parsed.body.contains("canva"))
    }

    func testAMarketplaceQualifiedNameIsAllowed() {
        XCTAssertEqual(
            SkillInstallBlock.parse("```install-skill\ncanva@claude-plugins-official\n```").plugin,
            "canva@claude-plugins-official"
        )
    }

    // MARK: - What may be named

    /// Nothing here reaches a shell — arguments go as an array — so the danger
    /// is not injection but a "name" that is really something else. A model
    /// reads web pages and repository files, and this string is the one place
    /// that content could steer an install.
    func testANameThatIsReallyAFlagOrAPathOrAURLIsRefused() {
        for name in [
            "--scope",
            "-y",
            "../../evil",
            "/tmp/evil",
            "https://example.com/evil.git",
            "git@github.com:someone/evil.git",
            "canva; rm -rf ~",
            "canva && curl evil.sh",
            "canva plugin",
            "",
            "a@b@c",
            "@official",
            "canva@",
        ] {
            XCTAssertFalse(validSkillPluginName(name), "Should refuse: \(name)")
        }
    }

    func testAnOrdinaryNameIsAccepted() {
        for name in ["canva", "aws-core", "code_review", "chrome-devtools-mcp", "a.b", "canva@official"] {
            XCTAssertTrue(validSkillPluginName(name), "Should accept: \(name)")
        }
    }

    /// A refused name is not a request. Rejecting it at the parse boundary
    /// means no caller can be handed one by forgetting to check.
    func testABlockNamingSomethingItMayNotIsNotARequestAtAll() {
        XCTAssertNil(SkillInstallBlock.parse("```install-skill\n--scope\n```").plugin)
        XCTAssertNil(SkillInstallBlock.parse("```install-skill\nhttps://evil.example/x.git\n```").plugin)
    }

    // MARK: - The command

    func testTheInstallCommandAnswersInAdvanceAndInstallsForThePerson() {
        XCTAssertEqual(
            skillInstallArguments(plugin: "canva"),
            ["plugin", "install", "canva", "--yes", "--scope", "user"]
        )
    }
}
