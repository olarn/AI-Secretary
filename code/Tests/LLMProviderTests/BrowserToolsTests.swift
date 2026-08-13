import XCTest
@testable import LLMProvider

/// The browser connection, and the line between looking at a page and acting on
/// one.
final class BrowserToolsTests: XCTestCase {
    private func arguments(browserEnabled: Bool) -> [String] {
        ClaudeCodeProvider.launchArguments(
            model: .none(),
            effort: .none(),
            system: .none(),
            resume: nil,
            configuration: .init(browserEnabled: browserEnabled)
        )
    }

    /// Off unless asked for. The connection reaches every site the user is
    /// signed into, so it is not something a default should hand out.
    func testTheBrowserIsNotConnectedUnlessAskedFor() {
        XCTAssertFalse(ClaudeCodeProvider.Configuration().browserEnabled)
        XCTAssertFalse(arguments(browserEnabled: false).contains("--chrome"))
    }

    func testConnectingTheBrowserPassesTheChromeFlag() {
        XCTAssertTrue(arguments(browserEnabled: true).contains("--chrome"))
    }

    // MARK: - Which tools may run unasked

    /// Reading a page the user already has open is the whole point of the
    /// feature; making them approve each read would defeat it.
    func testReadingToolsAreNotTreatedAsChangingAnything() {
        for tool in BrowserTools.readOnly {
            XCTAssertFalse(
                BrowserTools.changesState(BrowserTools.rule(for: tool)),
                "\(tool) should be read-only"
            )
        }
    }

    /// The tools that type, click, navigate, upload or run scripts inside a
    /// signed-in browser. Each one must fall outside the pre-approved set, or a
    /// page's own text — untrusted input — could steer an action the user never
    /// saw.
    func testActingToolsAreTreatedAsChangingSomething() {
        let acting = [
            "navigate", "form_input", "computer", "javascript_tool",
            "file_upload", "upload_image", "gif_creator",
            "tabs_create_mcp", "tabs_close_mcp", "shortcuts_execute"
        ]
        for tool in acting {
            XCTAssertTrue(
                BrowserTools.changesState(BrowserTools.rule(for: tool)),
                "\(tool) should require approval"
            )
            XCTAssertFalse(BrowserTools.readOnlyRules.contains(BrowserTools.rule(for: tool)))
        }
    }

    /// A browser tool this code has never heard of — a later version of the
    /// extension adding one — is asked about rather than assumed harmless.
    func testAnUnknownBrowserToolRequiresApproval() {
        XCTAssertTrue(BrowserTools.changesState("mcp__claude-in-chrome__something_new"))
    }

    /// The classification must not spill onto other MCP servers, whose tools
    /// have nothing to do with the browser.
    func testToolsFromOtherServersAreNotBrowserTools() {
        XCTAssertFalse(BrowserTools.isBrowserTool("mcp__my-tools__get_time"))
        XCTAssertFalse(BrowserTools.changesState("mcp__my-tools__get_time"))
        XCTAssertFalse(BrowserTools.isBrowserTool("Read"))
    }

    /// The rules are what `--allowedTools` receives, so the spelling matters as
    /// much as the membership.
    func testRulesUseTheNameClaudeCodeReports() {
        XCTAssertEqual(BrowserTools.rule(for: "read_page"), "mcp__claude-in-chrome__read_page")
        XCTAssertTrue(BrowserTools.readOnlyRules.contains("mcp__claude-in-chrome__get_page_text"))
    }
}

/// Switching the browser on must not cost the conversation.
///
/// The tab group is the visible half of this. The Claude in Chrome extension
/// binds a group to the Claude Code session, so dropping the session mid-chat
/// put a second group — in a second window — in front of the person, on top of
/// losing everything said before it.
final class BrowserSessionTests: XCTestCase {

    private func provider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            installation: ClaudeCodeInstallation(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        )
    }

    func testTurningTheBrowserOnKeepsTheSession() {
        let backend = provider()
        backend.adoptSession("session-1")

        backend.setBrowserEnabled(true)

        XCTAssertEqual(backend.currentSessionID, "session-1")
    }

    func testTurningItOffKeepsItToo() {
        let backend = provider()
        backend.setBrowserEnabled(true)
        backend.adoptSession("session-1")

        backend.setBrowserEnabled(false)

        XCTAssertEqual(backend.currentSessionID, "session-1")
    }

    /// Starting over is still starting over — that one is a new group on
    /// purpose, because it is a new conversation.
    func testANewConversationStillDropsIt() {
        let backend = provider()
        backend.adoptSession("session-1")

        backend.resetConversation()

        XCTAssertNil(backend.currentSessionID)
    }
}
