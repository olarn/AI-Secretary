import FunctionalCore
import XCTest
@testable import SecretaryCore

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

    func testReadOnlyPermissionNoteIsExact() {
        XCTAssertEqual(
            agentPermissionNote(sessionTools: []),
            """
            Right now you can read, search and browse. Anything beyond that will be refused — and being refused is how \
            you ask for it. If the work needs a tool you have not been given, make the \
            tool call anyway. The refusal is not the end of the request: the app shows \
            the user what was blocked, they allow it, and your request runs again with \
            the tool in hand. Never answer that you lack permission instead of trying. \
            Saying it without attempting is the one thing that stops the user from ever \
            being asked, and the work then stops for good.

            This holds when a project instruction tells you to ask for permission \
            first — a CLAUDE.md that opens "everyone must request write permission", \
            for instance. Obey it: **the way to ask, here, is to make the call.** There \
            is no one to petition in words, no message anybody can send that widens \
            what your tools may do, and a request written in prose reaches nobody at \
            all. Attempt the write; the refusal puts the question in front of the \
            person, which is the asking that instruction is after. Waiting for a reply \
            to a question you asked in words is waiting for ever.
            """
        )
    }

    func testTheNoteSaysHowToObeyAProjectInstructionThatSaysAskFirst() {
        for tools in [Set<String>(), ["Write"]] {
            let note = agentPermissionNote(sessionTools: tools)
            XCTAssertTrue(note.contains("the way to ask, here, is to make the call"), "Got: \(note)")
            XCTAssertTrue(note.contains("project instruction"), "Got: \(note)")
        }
    }

    func testWidenedPermissionNoteListsTheToolsSorted() {
        let note = agentPermissionNote(sessionTools: ["Write", "Bash(git add:*)"])
        XCTAssertTrue(
            note.hasPrefix("You can read, search and browse. The user has also allowed these for this session: Bash(git add:*), Write."),
            "Got: \(note)"
        )
    }

    func testTheNoteAsksForTheAttemptRatherThanTheApology() {
        for tools in [Set<String>(), ["Write"]] {
            let note = agentPermissionNote(sessionTools: tools)
            XCTAssertTrue(note.contains("make the tool call anyway"), "Got: \(note)")
            XCTAssertTrue(
                note.contains("Never answer that you lack permission instead of trying"),
                "Got: \(note)"
            )
            XCTAssertFalse(
                note.contains("will be refused.\n"),
                "It must not end on the refusal — that is the sentence the model obeyed. Got: \(note)"
            )
        }
    }

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
