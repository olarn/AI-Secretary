import FunctionalCore
import XCTest
@testable import SecretaryCore

/// The prompt assembly rules, now that they are functions of plain values.
///
/// The full texts are pinned indirectly by the turn-level tests that assert
/// what a `Secretary` actually sends; these check the *decisions* — which
/// pieces appear under which inputs — with exact equality where the whole
/// text is short enough to pin.
final class SecretaryPromptsTests: XCTestCase {
    private func agentPrompt(
        projectName: Option<String> = .some("Alpha"),
        others: [String] = [],
        browser: Bool = false,
        tools: Set<String> = []
    ) -> String {
        agentSystemPrompt(
            profileDescription: "You are Miku.",
            projectName: projectName,
            otherProjectNames: others,
            browserEnabled: browser,
            webHosts: [],
            sessionTools: tools,
            selectedSkills: []
        )
    }

    // MARK: - The permission note

    /// Exact, both branches: this is the sentence that stops the model
    /// retrying what was just approved — or claiming powers it lost.
    func testReadOnlyPermissionNoteIsExact() {
        XCTAssertEqual(
            agentPermissionNote(sessionTools: []),
            """
            Right now your tools are read-only: you can read, search and browse, \
            but writing or running commands will be refused.
            """
        )
    }

    func testWidenedPermissionNoteListsTheToolsSorted() {
        XCTAssertEqual(
            agentPermissionNote(sessionTools: ["Write", "Bash(git add:*)"]),
            """
            You can read, search and browse. The user has also allowed these for this \
            session: Bash(git add:*), Write. Anything \
            beyond that is still refused.
            """
        )
    }

    // MARK: - Which pieces appear

    func testBrowserNoteFollowsTheSwitch() {
        XCTAssertTrue(agentPrompt(browser: false).contains("You cannot see the person's browser"))
        XCTAssertTrue(agentPrompt(browser: true).contains("connected to the person's Chrome"))
    }

    func testOtherProjectsAppearOnlyWhenThereAreAny() {
        XCTAssertFalse(agentPrompt().contains("other folders the user has approved"))
        let prompt = agentPrompt(others: ["Beta", "Gamma"])
        XCTAssertTrue(prompt.contains("“Beta”, “Gamma”"))
    }

    func testTheAgentIsToldWhereItIsStanding() {
        XCTAssertTrue(agentPrompt().contains("inside the project “Alpha”"))
        XCTAssertTrue(agentPrompt(projectName: .none()).contains("inside a scratch folder"))
    }

    /// The chat-only prompt must keep saying "cannot run commands yourself" —
    /// and the agent prompt must never contain it. Sending the wrong one is the
    /// failure the doc comment on `agentSystemPrompt` records.
    func testOnlyTheChatOnlyPromptDisclaimsRunningCommands() {
        let chatOnly = chatOnlySystemPrompt(profileDescription: "You are Miku.", projectNames: ["Alpha"])
        XCTAssertTrue(chatOnly.contains("cannot run commands yourself"))
        XCTAssertFalse(agentPrompt().contains("cannot run commands yourself"))
        XCTAssertTrue(agentPrompt().contains("you are the one who acts"))
    }

    func testChatOnlyPromptWithNoProjectsSaysSo() {
        let prompt = chatOnlySystemPrompt(profileDescription: "You are Miku.", projectNames: [])
        XCTAssertTrue(prompt.hasSuffix("The user has not registered any projects yet."))
    }
}
