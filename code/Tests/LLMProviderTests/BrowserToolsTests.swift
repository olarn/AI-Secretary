import XCTest
@testable import LLMProvider

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

    func testTheBrowserIsNotConnectedUnlessAskedFor() {
        XCTAssertFalse(ClaudeCodeProvider.Configuration().browserEnabled)
        XCTAssertFalse(arguments(browserEnabled: false).contains("--chrome"))
    }

    func testConnectingTheBrowserPassesTheChromeFlag() {
        XCTAssertTrue(arguments(browserEnabled: true).contains("--chrome"))
    }

    func testReadingToolsAreNotTreatedAsChangingAnything() {
        for tool in BrowserTools.readOnly {
            XCTAssertFalse(
                BrowserTools.changesState(BrowserTools.rule(for: tool)),
                "\(tool) should be read-only"
            )
        }
    }

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

    func testAnUnknownBrowserToolRequiresApproval() {
        XCTAssertTrue(BrowserTools.changesState("mcp__claude-in-chrome__something_new"))
    }

    func testToolsFromOtherServersAreNotBrowserTools() {
        XCTAssertFalse(BrowserTools.isBrowserTool("mcp__my-tools__get_time"))
        XCTAssertFalse(BrowserTools.changesState("mcp__my-tools__get_time"))
        XCTAssertFalse(BrowserTools.isBrowserTool("Read"))
    }

    func testRulesUseTheNameClaudeCodeReports() {
        XCTAssertEqual(BrowserTools.rule(for: "read_page"), "mcp__claude-in-chrome__read_page")
        XCTAssertTrue(BrowserTools.readOnlyRules.contains("mcp__claude-in-chrome__get_page_text"))
    }
}

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

    func testANewConversationStillDropsIt() {
        let backend = provider()
        backend.adoptSession("session-1")

        backend.resetConversation()

        XCTAssertNil(backend.currentSessionID)
    }
}
