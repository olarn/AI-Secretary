import FunctionalCore
import XCTest
import AssistantState
import ProjectRegistry
import Permissions
import ToolAdapters
import LLMProvider
@testable import SecretaryCore

final class SpyWorkspaceProvider: ChatProvider, WorkspaceScopedProvider, SkillInstalling, @unchecked Sendable {
    private(set) var installedSkills: [String] = []
    var installOutcome: Either<String, String> = .right("installed")

    func installSkill(named plugin: String) async -> Either<String, String> {
        installedSkills.append(plugin)
        return installOutcome
    }

    private(set) var preparedDirectories: [URL?] = []
    private(set) var preparedTools: [[String]?] = []
    private(set) var callCount = 0
    private(set) var lastMessages: [ChatMessage] = []
    private(set) var lastSystem: String?
    private(set) var lastModel: ChatModel?
    private(set) var resetCount = 0
    var hasWorkspaceTools = true
    var denialsForNextTurn: [DeniedTool] = []
    var activityForNextTurn: [AgentActivity] = []
    var replyForNextTurn: String?
    var eventsForNextTurn: [ChatStreamEvent]?

    private(set) var preparedExtras: [[URL]] = []

    func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?) {
        preparedDirectories.append(workingDirectory)
        preparedExtras.append(additionalDirectories)
        preparedTools.append(allowedTools)
    }

    func resetConversation() { resetCount += 1; currentSessionID = nil }

    var currentSessionID: String?
    private(set) var adoptedSessions: [String?] = []
    func adoptSession(_ id: String?) {
        adoptedSessions.append(id)
        currentSessionID = id
    }

    var supportsBrowser = true
    private(set) var browserEnabledCalls: [Bool] = []
    func setBrowserEnabled(_ enabled: Bool) { browserEnabledCalls.append(enabled) }

    func stream(
        messages: [ChatMessage],
        model: Option<ChatModel>,
        effort: Option<Effort>,
        maxTokens: Int,
        system: Option<String>
    ) -> ChatStream {
        callCount += 1
        lastMessages = messages
        lastSystem = system.toOptional()
        lastModel = model.toOptional()
        let denials = denialsForNextTurn
        denialsForNextTurn = []
        let steps = activityForNextTurn
        activityForNextTurn = []
        let text = replyForNextTurn ?? "ok"
        replyForNextTurn = nil
        if let scripted = eventsForNextTurn {
            eventsForNextTurn = nil
            return AsyncStream { continuation in
                for event in scripted { continuation.yield(.right(event)) }
                continuation.finish()
            }
        }
        return AsyncStream { continuation in
            for step in steps { continuation.yield(.right(.activity(step))) }
            for denial in denials { continuation.yield(.right(.toolDenied(denial))) }
            continuation.yield(.right(.textDelta(text)))
            continuation.yield(.right(.completed(stopReason: .none(), usage: .none())))
            continuation.finish()
        }
    }
}

@MainActor
final class AgentSessionTests: XCTestCase {
    private var machine: AssistantStateMachine!
    private var provider: SpyWorkspaceProvider!
    private var store: InMemoryProjectStore!
    private var activityPreference: InMemoryActivityPreference!
    private var registry: ProjectRegistry!

    private let projectPath = "/tmp/agent-fixture"

    override func setUp() {
        super.setUp()
        machine = AssistantStateMachine()
        provider = SpyWorkspaceProvider()
        activityPreference = InMemoryActivityPreference(showsActivity: true)
    }

    private func makeSecretary(
        projects: [Project],
        grantStore: StandingGrantStoring = InMemoryStandingGrantStore()
    ) -> Secretary {
        store = InMemoryProjectStore(projects: projects)
        registry = ProjectRegistry(store: store)
        return Secretary(
            stateMachine: machine,
            registry: registry,
            adapter: SpyAdapter(),
            fileAdapter: SpyFileAdapter(),
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            activityPreference: activityPreference,
            chatProvider: provider,
            grantStore: grantStore
        )
    }

    private func project(grantingAgent: Bool) -> Project {
        Project(
            name: "Fixture",
            path: projectPath,
            allowedTools: grantingAgent
                ? [FileReadOnlyAdapter.toolIdentifier, Secretary.claudeCodeToolID]
                : [FileReadOnlyAdapter.toolIdentifier]
        )
    }

    private func waitUntilIdle(timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while machine.state != .idle && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testFirstMessageInAnUngrantedProjectAsksBeforeRunningAnything() {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("what does this project do?")

        guard case .approval(let request, let operation) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected an approval request")
        }
        XCTAssertEqual(request.toolID, Secretary.claudeCodeToolID)
        XCTAssertEqual(operation, .startAgent(prompt: "what does this project do?"))
        XCTAssertEqual(provider.callCount, 0, "Nothing may run before approval")
        XCTAssertTrue(provider.preparedDirectories.isEmpty)
    }

    func testTheApprovalPromptSaysItRunsOnTheUsersClaudeCodeAccount() {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("hello")

        let prompt = secretary.transcript.last?.text ?? ""
        XCTAssertTrue(prompt.contains("Claude Code"), "Got: \(prompt)")
        XCTAssertTrue(prompt.contains("Fixture"), "Should name the project. Got: \(prompt)")
    }

    func testApprovingPersistsTheGrantAndRunsTheOriginalMessage() async throws {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("summarise this repo please")
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        XCTAssertEqual(provider.callCount, 1, "The interrupted message should run after approval")
        XCTAssertEqual(provider.lastMessages.last?.content, "summarise this repo please")
        XCTAssertEqual(provider.preparedDirectories.last??.path, projectPath)

        let saved = try XCTUnwrap(store.load().getOrElse([]).first)
        XCTAssertTrue(saved.allowedTools.contains(Secretary.claudeCodeToolID),
                      "The grant must survive a relaunch")
    }

    func testDenyingRunsNothingAndDoesNotPersistAGrant() async throws {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("hello")
        secretary.resolvePendingApproval(granted: false)

        XCTAssertEqual(provider.callCount, 0)
        let saved = try XCTUnwrap(store.load().getOrElse([]).first)
        XCTAssertFalse(saved.allowedTools.contains(Secretary.claudeCodeToolID))
    }

    func testAnAlreadyGrantedProjectRunsWithoutAsking() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertEqual(secretary.pendingDecision, .none())
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(provider.preparedDirectories.last??.path, projectPath)
    }

    func testAskingOnlyHappensOncePerProject() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("first")
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        secretary.submit("second")
        await waitUntilIdle()

        XCTAssertEqual(secretary.pendingDecision, .none(), "The second message must not ask again")
        XCTAssertEqual(provider.callCount, 2)
    }

    func testAnAgentBackendIsNeverToldItCannotAct() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("สรุปเนื้อหาให้ฟังหน่อย")
        await waitUntilIdle()

        let prompt = try? XCTUnwrap(provider.lastSystem)
        XCTAssertFalse(prompt?.contains("cannot run commands") == true,
                       "Got: \(prompt ?? "-")")
        XCTAssertFalse(prompt?.contains("tell the \nuser the exact command") == true)
        XCTAssertTrue(prompt?.contains("look for yourself") == true,
                      "It should be told to open files itself. Got: \(prompt ?? "-")")
    }

    func testTheAgentPromptDescribesEveryMarkerBlockTheAppUnderstands() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        let prompt = provider.lastSystem ?? "-"
        for fence in [MessageChoices.fence, LoopBlock.fence, InfoWindowBlock.fence] {
            XCTAssertTrue(prompt.contains(fence), "\(fence) is not described. Got: \(prompt)")
        }
    }

    func testTheAgentIsToldToFinishTheEarlierRequest() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertTrue(
            (provider.lastSystem ?? "-").contains(Secretary.resumePrompt),
            "The prompt must say what to do when the missing piece arrives."
        )
    }

    func testTheChatOnlyPromptCarriesTheSameRules() async {
        provider.hasWorkspaceTools = false
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        let prompt = provider.lastSystem ?? "-"
        XCTAssertTrue(prompt.contains(Secretary.resumePrompt), "resume rule missing")
        XCTAssertTrue(prompt.contains(Secretary.languagePrompt), "language rule missing")
        for fence in [LoopBlock.fence, InfoWindowBlock.fence] {
            XCTAssertTrue(prompt.contains(fence), "\(fence) is not described. Got: \(prompt)")
        }
    }

    func testTheAgentIsAskedToAnswerInTheLanguageItWasWrittenTo() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("สวัสดี ช่วยดูโปรเจกต์ให้หน่อย")
        await waitUntilIdle()

        XCTAssertTrue((provider.lastSystem ?? "-").contains(Secretary.languagePrompt))
    }

    func testTheLanguageRuleDoesNotAskForEverythingToBeTranslated() {
        XCTAssertTrue(Secretary.languagePrompt.contains("technical terms"))
        XCTAssertTrue(Secretary.languagePrompt.contains("error text"))
    }

    func testThePersonalityDoesNotDecideTheLanguage() {
        let profile = SecretaryProfile(
            name: "Miku",
            personality: "ร่าเริง เป็นกันเอง ชอบช่วยงาน"
        )
        XCTAssertFalse(profile.promptDescription.contains("answer in English."))
        XCTAssertTrue(profile.promptDescription.contains("decided by the person's"))
    }

    func testAddingAProjectRunsTheLastQuestionAgain() async {
        let secretary = makeSecretary(projects: [])
        secretary.submit("what is in the ratebook?")
        await waitUntilIdle()
        let before = provider.callCount

        _ = registry.add(project(grantingAgent: true))
        secretary.projectsDidChange()
        await waitUntilIdle()

        XCTAssertEqual(provider.callCount, before + 1, "The earlier question should have been re-sent")
        XCTAssertEqual(
            provider.lastMessages.last(where: { $0.role == .user })?.content,
            "what is in the ratebook?"
        )
        XCTAssertTrue(
            secretary.transcript.contains { $0.kind == .activity && $0.text.contains("asking again") },
            "An answer nobody just asked for has to say why it appeared"
        )
    }

    func testAddingAProjectWithNoConversationAsksNothing() async {
        let secretary = makeSecretary(projects: [])
        let before = provider.callCount
        secretary.projectsDidChange()
        await waitUntilIdle()
        XCTAssertEqual(provider.callCount, before)
    }

    func testABlockedTurnPutsTheRequestBackInFrontOfTheModel() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.replyForNextTurn = """
        The folder is empty.

        ```blocked
        a project whose MCP serves ratebook data
        ```
        """
        secretary.submit("ratebook for Vios and City 2022, and pin it")
        await waitUntilIdle()

        XCTAssertFalse(
            secretary.transcript.contains { $0.text.contains("```blocked") },
            "The marker is for the app, not the eye"
        )

        secretary.submit("from the project's MCP")
        await waitUntilIdle()

        let prompt = provider.lastSystem ?? "-"
        XCTAssertTrue(prompt.contains("ratebook for Vios and City 2022, and pin it"),
                      "The unfinished request must be named. Got: \(prompt)")
        XCTAssertTrue(prompt.contains("a project whose MCP serves ratebook data"))
    }

    func testACompletedTurnClearsTheReminder() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.replyForNextTurn = "nope\n```blocked\na path\n```"
        secretary.submit("first question")
        await waitUntilIdle()

        secretary.submit("second question")
        await waitUntilIdle()
        secretary.submit("third question")
        await waitUntilIdle()

        XCTAssertFalse(
            (provider.lastSystem ?? "").contains("UNFINISHED REQUEST"),
            "The second turn completed, so the third must not still be reminded"
        )
    }

    func testTheAgentPromptNamesTheProjectItIsStandingIn() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertTrue(provider.lastSystem?.contains("Fixture") == true,
                      "Got: \(provider.lastSystem ?? "-")")
    }

    func testAChatOnlyBackendKeepsTheAdviceToTypeCommands() async {
        provider.hasWorkspaceTools = false
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertTrue(provider.lastSystem?.contains("cannot run commands") == true,
                      "Got: \(provider.lastSystem ?? "-")")
    }

    private func denyWrite() -> DeniedTool {
        DeniedTool(name: "Write", target: .some("/tmp/agent-fixture/out.txt"), rules: ["Write"])
    }

    private func denyFolder() -> DeniedTool {
        DeniedTool(
            name: "Write",
            target: .some("/tmp/elsewhere/task.md"),
            rules: ["Write"],
            directory: .some("/tmp/elsewhere")
        )
    }

    func testAFolderRefusalPutsACardUp() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyFolder()]
        secretary.submit("write the action items")
        await waitUntilIdle()

        guard case .approval(let request, let operation) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected a card, got: \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(operation, .widenAgentDirectories(paths: ["/tmp/elsewhere"], prompt: "write the action items"))
        XCTAssertEqual(request.actionClass, .directoryAccess)
        XCTAssertTrue(
            secretary.transcript.contains { $0.text.contains("/tmp/elsewhere") },
            "The card has to name the folder being agreed to"
        )
    }

    func testOpeningAFolderIsNeverRememberedAndSaysSo() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyFolder()]
        secretary.submit("write the action items")
        await waitUntilIdle()

        XCTAssertEqual(secretary.offeredApprovalAnswers, [.once, .deny])
    }

    func testTheFolderCardIsAnnouncedToTheCommandWindow() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        var asked: [ApprovalAsked] = []
        secretary.onApprovalAsked = { asked.append($0) }

        provider.denialsForNextTurn = [denyFolder()]
        secretary.submit("write the action items")
        await waitUntilIdle()

        XCTAssertEqual(asked.count, 1, "Got: \(asked)")
        XCTAssertTrue(asked.first?.question.contains("/tmp/elsewhere") ?? false)
    }

    func testSayingYesOpensTheFolderAndRetries() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyFolder()]
        secretary.submit("write the action items")
        await waitUntilIdle()

        let before = provider.callCount
        secretary.resolvePendingApproval(answer: .once)
        await waitUntilIdle()

        XCTAssertGreaterThan(provider.callCount, before, "the request has to run again")
        XCTAssertTrue(
            provider.preparedExtras.last?.contains(where: { $0.path == "/tmp/elsewhere" }) ?? false,
            "the folder has to be handed to the backend. Got: \(String(describing: provider.preparedExtras.last))"
        )
    }

    func testAFolderIsAskedForFirstAndTheToolWallStillArrives() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyFolder()]
        secretary.submit("write the action items")
        await waitUntilIdle()

        guard case .approval(_, let first) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected the folder card")
        }
        XCTAssertEqual(first, .widenAgentDirectories(paths: ["/tmp/elsewhere"], prompt: "write the action items"))

        provider.denialsForNextTurn = [denyWrite()]
        secretary.resolvePendingApproval(answer: .once)
        await waitUntilIdle()

        guard case .approval(_, let second) = secretary.pendingDecision.toOptional() else {
            return XCTFail("The tool refusal has to get its own card, not be swallowed")
        }
        XCTAssertEqual(second, .widenAgentTools(rules: ["Write"], prompt: "write the action items"))
    }

    func testAFolderAlreadyOpenIsNotOfferedAgainAndIsNotSilent() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyFolder()]
        secretary.submit("write the action items")
        await waitUntilIdle()
        secretary.resolvePendingApproval(answer: .once)
        await waitUntilIdle()

        provider.denialsForNextTurn = [
            DeniedTool(name: "Write", target: .some("/tmp/elsewhere/task.md"), rules: [], directory: .some("/tmp/elsewhere"))
        ]
        secretary.submit("try again")
        await waitUntilIdle()

        XCTAssertEqual(
            secretary.pendingDecision, .none(),
            "Offering a folder that is already open is a button that does nothing"
        )
        XCTAssertTrue(
            secretary.transcript.contains { $0.text.contains("already let me work there") },
            "and it has to say so. Got: \(secretary.transcript.map(\.text).joined(separator: " | "))"
        )
    }

    func testAReplyBlockedOnAPermissionIsToldThatAttemptingIsTheAsking() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.replyForNextTurn = """
        As CLAUDE.md says, I have to ask for write permission first.

        ```blocked
        write permission for 2.actions/task.md
        ```
        """
        secretary.submit("write the action items")
        await waitUntilIdle()

        XCTAssertTrue(
            provider.lastMessages.contains { $0.content.contains("Asking, here, means making the call") },
            "Got: \(provider.lastMessages.map(\.content).joined(separator: " | "))"
        )
    }

    func testTheNudgeIsSpentOnceOnADeadEnd() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        let blockedReply = """
        Still waiting for permission.

        ```blocked
        write permission for 2.actions/task.md
        ```
        """
        provider.replyForNextTurn = blockedReply
        secretary.submit("write the action items")
        await waitUntilIdle()
        let afterFirst = provider.callCount

        provider.replyForNextTurn = blockedReply
        await waitUntilIdle()
        XCTAssertLessThanOrEqual(
            provider.callCount, afterFirst + 1,
            "A second dead end must not start a third turn"
        )
    }

    func testAnOrdinaryBlockedReplyIsLeftAlone() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.replyForNextTurn = """
        I couldn't find it.

        ```blocked
        which folder the ratebook is in
        ```
        """
        secretary.submit("find the ratebook")
        await waitUntilIdle()

        XCTAssertFalse(
            provider.lastMessages.contains { $0.content.contains("Asking, here, means making the call") },
            "Only a permission is the kind of missing nobody can hand over"
        )
    }

    func testNothingIsNudgedWhileACardIsWaiting() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("write the action items")
        await waitUntilIdle()
        XCTAssertTrue(secretary.pendingDecision.isDefined, "Expected the project card")

        XCTAssertFalse(
            provider.lastMessages.contains { $0.content.contains("Asking, here, means making the call") }
        )
    }

    func testARaisedCardIsAnnouncedToWhoeverIsListening() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        var asked: [ApprovalAsked] = []
        secretary.onApprovalAsked = { asked.append($0) }

        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()

        XCTAssertEqual(asked.count, 1, "Got: \(asked)")
        XCTAssertTrue(asked.first?.question.contains("out.txt") ?? false,
                      "It has to carry the words, not a summary. Got: \(String(describing: asked.first))")
        XCTAssertEqual(asked.first?.answers, secretary.offeredApprovalAnswers)
        XCTAssertFalse(asked.first?.answers.isEmpty ?? true)
    }

    func testTheCardBeingSettledIsAnnouncedToo() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        var settled = 0
        secretary.onApprovalSettled = { settled += 1 }

        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()
        XCTAssertEqual(settled, 0, "Nothing is settled while the card is still up")

        secretary.resolvePendingApproval(answer: .deny)
        XCTAssertEqual(settled, 1)
    }

    func testTypingSomethingElseTakesTheCardDownEverywhere() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        var settled = 0
        secretary.onApprovalSettled = { settled += 1 }

        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()

        secretary.submit("never mind")
        await waitUntilIdle()
        XCTAssertGreaterThanOrEqual(settled, 1)
        XCTAssertEqual(secretary.pendingDecision, .none())
    }

    func testNothingIsAnnouncedWhenNoCardGoesUp() async {
        let allowed = project(grantingAgent: true)
        let secretary = makeSecretary(
            projects: [allowed],
            grantStore: InMemoryStandingGrantStore(grants: [
                StandingGrant(
                    projectID: allowed.id,
                    toolID: Secretary.claudeCodeToolID,
                    actionClass: .localWrite
                )
            ])
        )
        var asked: [ApprovalAsked] = []
        secretary.onApprovalAsked = { asked.append($0) }

        secretary.submit("hello")
        await waitUntilIdle()
        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()

        XCTAssertEqual(asked, [], "A silent widen must not put a question in front of anyone")
    }

    func testARefusedToolOffersToAllowItAndTryAgain() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()

        guard case .approval(let request, let operation) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected an offer to widen, got: \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(operation, .widenAgentTools(rules: ["Write"], prompt: "create out.txt"))
        XCTAssertEqual(request.actionClass, .localWrite, "Writing files must never be approve-once")
        XCTAssertTrue(secretary.transcript.contains { $0.text.contains("out.txt") },
                      "The prompt should say what was blocked")
    }

    func testAProjectWithAStandingWriteGrantIsNotAskedAgain() async {
        let allowed = project(grantingAgent: true)
        let secretary = makeSecretary(
            projects: [allowed],
            grantStore: InMemoryStandingGrantStore(grants: [
                StandingGrant(
                    projectID: allowed.id,
                    toolID: Secretary.claudeCodeToolID,
                    actionClass: .localWrite
                )
            ])
        )
        secretary.submit("hello")
        await waitUntilIdle()

        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()

        XCTAssertEqual(
            secretary.pendingDecision, .none(),
            "A project already answered Always for must not raise the card again"
        )
        XCTAssertFalse(
            secretary.transcript.contains { $0.text.contains("Shall I go ahead?") },
            "Nor may it ask in prose. Got: \(secretary.transcript.map(\.text).joined(separator: " | "))"
        )
    }

    func testARuleAlreadyGrantedAndStillRefusedRaisesTheCardAgain() async {
        let allowed = project(grantingAgent: true)
        let secretary = makeSecretary(
            projects: [allowed],
            grantStore: InMemoryStandingGrantStore(grants: [
                StandingGrant(
                    projectID: allowed.id,
                    toolID: Secretary.claudeCodeToolID,
                    actionClass: .localWrite
                )
            ])
        )
        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()
        XCTAssertEqual(secretary.pendingDecision, .none(), "the first one is silent")

        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt again")
        await waitUntilIdle()

        guard case .approval = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected the card back, got: \(String(describing: secretary.pendingDecision))")
        }
    }

    func testAnsweringAlwaysOnTheWidenCardIsWrittenDown() async {
        let allowed = project(grantingAgent: true)
        let grantStore = InMemoryStandingGrantStore()
        let secretary = makeSecretary(projects: [allowed], grantStore: grantStore)
        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()

        secretary.resolvePendingApproval(answer: .always)
        await waitUntilIdle()

        XCTAssertEqual(
            grantStore.load().getOrElse([]),
            [StandingGrant(
                projectID: allowed.id,
                toolID: Secretary.claudeCodeToolID,
                actionClass: .localWrite
            )],
            "Exactly the one grant, and nothing about which rules were refused"
        )
        XCTAssertTrue(
            secretary.transcript.contains {
                $0.text.contains(chosenLine("Always")) && $0.text.contains("keep this for")
            },
            "Always on a write card must say the grant was kept"
        )
    }

    func testAnsweringOnceOnTheWidenCardIsNotWrittenDown() async {
        let allowed = project(grantingAgent: true)
        let grantStore = InMemoryStandingGrantStore()
        let secretary = makeSecretary(projects: [allowed], grantStore: grantStore)
        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()

        secretary.resolvePendingApproval(answer: .once)
        await waitUntilIdle()

        XCTAssertEqual(grantStore.load().getOrElse([]), [])
    }

    func testTheRetryDrivesTheStateMachineBackThroughBusy() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()
        XCTAssertEqual(machine.state, .idle)

        var sawBusy = false
        let watcher = Task { @MainActor in
            for _ in 0..<200 {
                if machine.state != .idle { sawBusy = true; return }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        secretary.resolvePendingApproval(granted: true)
        await watcher.value
        await waitUntilIdle()

        XCTAssertTrue(sawBusy, "The retry must show as work in progress")
        XCTAssertEqual(machine.state, .idle)
    }

    func testApprovingRetriesWithTheToolAllowed() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        XCTAssertEqual(provider.callCount, 2, "The blocked request should be retried")
        XCTAssertTrue(provider.preparedTools.last??.contains("Write") == true,
                      "Got: \(String(describing: provider.preparedTools.last ?? nil))")
    }

    func testDenyingDoesNotRetryAndLeavesToolsClosed() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()
        secretary.resolvePendingApproval(granted: false)
        await waitUntilIdle()

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertFalse(provider.preparedTools.last??.contains("Write") == true)
    }

    func testAWriteGrantIsNotWrittenToTheProjectFile() async throws {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()
        secretary.resolvePendingApproval(granted: true)
        await waitUntilIdle()

        let saved = try XCTUnwrap(store.load().getOrElse([]).first)
        XCTAssertFalse(saved.allowedTools.contains("Write"),
                       "A write grant must not survive a relaunch: \(saved.allowedTools)")
    }

    func testSeveralRefusalsAreCollectedIntoOneQuestion() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [
            denyWrite(),
            DeniedTool(name: "Bash", target: .some("npm test"), rules: ["Bash(npm test *)"]),
            denyWrite()
        ]
        secretary.submit("set the project up")
        await waitUntilIdle()

        guard case .approval(_, let operation) = secretary.pendingDecision.toOptional(),
              case .widenAgentTools(let rules, _) = operation else {
            return XCTFail("Expected one combined offer")
        }
        XCTAssertEqual(rules, ["Write", "Bash(npm test *)"], "Duplicates should collapse")
    }

    func testAskingForASkillInstallsNothingUntilSomeoneSaysYes() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.replyForNextTurn = "I need Canva for this.\n\n```install-skill\ncanva\n```"

        secretary.submit("make me a poster")
        await waitUntilIdle()

        XCTAssertEqual(provider.installedSkills, [], "Nothing may be installed by asking")
        guard case .approval(let request, let operation) = secretary.pendingDecision.toOptional(),
              case .installSkill(let plugin, _) = operation else {
            return XCTFail("Expected an offer to install")
        }
        XCTAssertEqual(plugin, "canva")
        XCTAssertEqual(request.actionClass, .dependencyInstalling, "Installing software is never unattended")
        XCTAssertFalse(
            secretary.transcript.contains { $0.text.contains("install-skill") },
            "The block must not reach the screen"
        )
    }

    func testANameTheInstallerMayNotBeHandedRaisesNoOfferAtAll() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.replyForNextTurn = "```install-skill\nhttps://evil.example/x.git\n```"

        secretary.submit("make me a poster")
        await waitUntilIdle()

        XCTAssertEqual(secretary.pendingDecision, .none())
        XCTAssertEqual(provider.installedSkills, [])
    }

    func testMentioningASkillInProseRaisesNothing() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.replyForNextTurn = "You'd need the canva skill for that; you could install canva."

        secretary.submit("make me a poster")
        await waitUntilIdle()

        XCTAssertEqual(secretary.pendingDecision, .none())
        XCTAssertEqual(provider.installedSkills, [])
    }

    func testATurnWithNoRefusalsAsksNothing() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("just tell me about it")
        await waitUntilIdle()

        XCTAssertEqual(secretary.pendingDecision, .none())
    }

    func testPickingAModelIsAnnouncedInTheTranscript() {
        let secretary = makeSecretary(projects: [])
        secretary.selectModel(.some(.opus5))

        XCTAssertEqual(secretary.model, .some(.opus5))
        XCTAssertTrue(secretary.transcript.last?.text.contains("Claude Opus 5") == true,
                      "Got: \(secretary.transcript.last?.text ?? "-")")
    }

    func testGoingBackToTheInheritedDefaultIsAnnouncedToo() {
        let secretary = makeSecretary(projects: [])
        secretary.selectModel(.some(.opus5))
        secretary.selectModel(.none())

        XCTAssertEqual(secretary.model, Option.none())
        XCTAssertTrue(secretary.isModelInherited)
        XCTAssertTrue(secretary.transcript.last?.text.contains("the tool's own default") == true,
                      "Got: \(secretary.transcript.last?.text ?? "-")")
    }

    func testPickingTheSameValueSaysNothing() {
        let secretary = makeSecretary(projects: [])
        secretary.selectModel(.some(.opus5))
        let count = secretary.transcript.count
        secretary.selectModel(.some(.opus5))

        XCTAssertEqual(secretary.transcript.count, count, "No change, nothing to announce")
    }

    func testPickingAnEffortIsAnnounced() {
        let secretary = makeSecretary(projects: [])
        secretary.selectEffort(.some(.xhigh))

        XCTAssertEqual(secretary.effort, .some(.xhigh))
        XCTAssertFalse(secretary.isEffortInherited)
        XCTAssertTrue(secretary.transcript.last?.text.contains("xhigh") == true)
    }

    func testAPickedModelIsUsedForTheNextTurn() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.selectModel(.some(.fable5))
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertEqual(provider.lastModel, .fable5)
    }

    func testActivityIsCollectedForTheTurn() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.activityForNextTurn = [
            AgentActivity(kind: .thinking, detail: "Thinking"),
            AgentActivity(kind: .tool, detail: "Read: about.md")
        ]
        secretary.submit("what's in here?")
        await waitUntilIdle()

        XCTAssertEqual(secretary.activity.map(\.detail), ["Thinking", "Read: about.md"])
    }

    func testRepeatedIdenticalStepsCollapse() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        let thinking = AgentActivity(kind: .thinking, detail: "Thinking")
        provider.activityForNextTurn = [thinking, thinking, thinking]
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertEqual(secretary.activity.count, 1)
    }

    func testActivityAppearsInTheTranscriptBeforeTheReply() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.activityForNextTurn = [AgentActivity(kind: .tool, detail: "Read: about.md")]
        secretary.submit("what's in here?")
        await waitUntilIdle()

        let kinds = secretary.transcript.map(\.kind)
        guard let activityIndex = kinds.firstIndex(of: .activity) else {
            return XCTFail("Expected an activity entry, got: \(kinds)")
        }
        XCTAssertTrue(secretary.transcript[activityIndex].text.contains("about.md"))
        XCTAssertEqual(activityIndex, secretary.transcript.count - 2,
                       "It should sit just before the reply it preceded")
    }

    func testAllStepsOfATurnShareOneEntryRatherThanFlooding() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.activityForNextTurn = [
            AgentActivity(kind: .thinking, detail: "Thinking"),
            AgentActivity(kind: .tool, detail: "Read: a.md"),
            AgentActivity(kind: .tool, detail: "Read: b.md")
        ]
        secretary.submit("hello")
        await waitUntilIdle()

        let entries = secretary.transcript.filter { $0.kind == .activity }
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].text.contains("a.md") && entries[0].text.contains("b.md"))
    }

    func testTurningItOffRemovesWhatWasShownAndSaysSo() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.activityForNextTurn = [AgentActivity(kind: .tool, detail: "Read: a.md")]
        secretary.submit("hello")
        await waitUntilIdle()
        XCTAssertTrue(secretary.transcript.contains { $0.kind == .activity })

        secretary.toggleActivityVisibility()

        XCTAssertFalse(secretary.showsActivity)
        let boxes = secretary.transcript.filter { $0.kind == .activity }
        XCTAssertEqual(boxes.count, 1, "Only the announcement itself should remain")
        XCTAssertTrue(boxes.last?.text.contains("Hiding") == true,
                      "The change should be announced: \(boxes.last?.text ?? "-")")
    }

    func testItIsHiddenOnAFirstRun() {
        activityPreference = InMemoryActivityPreference()
        let secretary = makeSecretary(projects: [])
        XCTAssertFalse(secretary.showsActivity)
    }

    func testTheChoiceIsRememberedForNextTime() {
        activityPreference = InMemoryActivityPreference()
        let secretary = makeSecretary(projects: [])
        secretary.toggleActivityVisibility()

        XCTAssertTrue(activityPreference.showsActivity, "Should have been saved")
        let relaunched = makeSecretary(projects: [])
        XCTAssertTrue(relaunched.showsActivity)
    }

    func testTurningItBackOnSaysSoToo() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.toggleActivityVisibility()
        secretary.toggleActivityVisibility()

        XCTAssertTrue(secretary.showsActivity)
        let last = secretary.transcript.last
        XCTAssertEqual(last?.kind, .activity)
        XCTAssertTrue(last?.text.contains("Showing") == true, "Got: \(last?.text ?? "-")")
    }

    func testWithItOffNoActivityEntryIsAdded() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.toggleActivityVisibility()
        let countAfterToggle = secretary.transcript.filter { $0.kind == .activity }.count

        provider.activityForNextTurn = [AgentActivity(kind: .tool, detail: "Read: a.md")]
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertEqual(secretary.transcript.filter { $0.kind == .activity }.count, countAfterToggle,
                       "No box should be added for this turn's steps while hidden")
        XCTAssertFalse(secretary.activity.isEmpty, "Still collected, just not shown")
    }

    func testASecondTurnGetsItsOwnActivityEntry() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.activityForNextTurn = [AgentActivity(kind: .tool, detail: "Read: first.md")]
        secretary.submit("one")
        await waitUntilIdle()

        provider.activityForNextTurn = [AgentActivity(kind: .tool, detail: "Read: second.md")]
        secretary.submit("two")
        await waitUntilIdle()

        let boxes = secretary.transcript.filter { $0.kind == .activity }
        XCTAssertEqual(boxes.count, 2)
        XCTAssertTrue(boxes[0].text.contains("first.md"), "History must survive: \(boxes[0].text)")
        XCTAssertTrue(boxes[1].text.contains("second.md"))
    }

    func testActivityIsClearedWhenANewTurnStarts() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.activityForNextTurn = [AgentActivity(kind: .tool, detail: "Read: a.md")]
        secretary.submit("first")
        await waitUntilIdle()
        XCTAssertFalse(secretary.activity.isEmpty)

        secretary.submit("second")
        await waitUntilIdle()
        XCTAssertTrue(secretary.activity.isEmpty, "Got: \(secretary.activity.map(\.detail))")
    }

    func testWithNoProjectItRunsInAScratchDirectoryNotTheLaunchDirectory() async {
        let secretary = makeSecretary(projects: [])
        secretary.submit("hello")
        await waitUntilIdle()

        let directory = try? XCTUnwrap(provider.preparedDirectories.last ?? nil)
        XCTAssertEqual(directory?.lastPathComponent, "scratch")
        XCTAssertNotEqual(directory?.path, FileManager.default.currentDirectoryPath)
        XCTAssertEqual(provider.callCount, 1)
    }

    func testEveryApprovedProjectIsOpenAlongsideThePrimaryOne() async {
        let other = Project(name: "Other", path: "/tmp/other",
                            allowedTools: [Secretary.claudeCodeToolID])
        let secretary = makeSecretary(projects: [project(grantingAgent: true), other])
        secretary.submit("compare the two projects")
        await waitUntilIdle()

        XCTAssertEqual(provider.preparedDirectories.last??.path, projectPath)
        XCTAssertEqual(provider.preparedExtras.last?.map(\.path), ["/tmp/other"])
    }

    func testAnUnapprovedProjectIsNotOpened() async {
        let secret = Project(name: "Secret", path: "/tmp/secret", allowedTools: [])
        let secretary = makeSecretary(projects: [project(grantingAgent: true), secret])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertEqual(provider.preparedExtras.last, [], "An unapproved folder must stay closed")
    }

    func testTheAgentPromptMentionsTheOtherOpenProjects() async {
        let other = Project(name: "Other", path: "/tmp/other",
                            allowedTools: [Secretary.claudeCodeToolID])
        let secretary = makeSecretary(projects: [project(grantingAgent: true), other])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertTrue(provider.lastSystem?.contains("Other") == true,
                      "Got: \(provider.lastSystem ?? "-")")
    }

    func testSeveralUnapprovedProjectsAskWhichToStartIn() {
        let secretary = makeSecretary(projects: [
            project(grantingAgent: false),
            Project(name: "Other", path: "/tmp/other", allowedTools: [])
        ])
        secretary.submit("hello")

        guard case .projectChoice(let candidates, let operation) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected a project choice, got: \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(operation, .startAgent(prompt: "hello"))
        XCTAssertEqual(provider.callCount, 0)
    }

    func testChoosingAProjectThenAsksToApproveIt() {
        let secretary = makeSecretary(projects: [
            project(grantingAgent: false),
            Project(name: "Other", path: "/tmp/other", allowedTools: [])
        ])
        secretary.submit("hello")
        guard case .projectChoice(let candidates, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected a project choice")
        }
        secretary.choose(project: candidates[0])

        guard case .approval(let request, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected an approval request after choosing")
        }
        XCTAssertEqual(request.toolID, Secretary.claudeCodeToolID)
        XCTAssertEqual(provider.callCount, 0)
    }

    private func busySecretary() async -> Secretary {
        let secretary = makeSecretary(projects: [
            Project(name: "Fixture", path: projectPath, allowedTools: [Secretary.claudeCodeToolID])
        ])
        provider.eventsForNextTurn = [.textDelta("working on it")]
        secretary.submit("the first thing")
        let deadline = Date().addingTimeInterval(2)
        while !secretary.transcript.contains(where: { $0.text.contains("working on it") }),
              Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return secretary
    }

    func testTypingMidFlightAsksRatherThanTakingOver() async {
        let secretary = await busySecretary()
        secretary.submit("and another thing")

        guard case .interruption(let text, _, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected to be asked. Got: \(secretary.pendingDecision)")
        }
        XCTAssertEqual(text, "and another thing")
        XCTAssertEqual(provider.callCount, 1, "nothing new may start before the answer")
    }

    func testWaitingItsTurnQueuesRatherThanRuns() async {
        let secretary = await busySecretary()
        secretary.submit("and another thing")
        secretary.resolveInterruption(.wait)

        XCTAssertEqual(secretary.queuedMessages, ["and another thing"])
        XCTAssertEqual(provider.callCount, 1)
    }

    func testReplacingStopsTheRunningTurnAndStartsTheNewOne() async {
        let secretary = await busySecretary()
        secretary.submit("actually do this instead")
        provider.eventsForNextTurn = [
            .textDelta("done"),
            .completed(stopReason: .none(), usage: .none())
        ]
        secretary.resolveInterruption(.replace)
        await waitUntilIdle()

        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(provider.lastMessages.last?.content, "actually do this instead")
        XCTAssertTrue(secretary.queuedMessages.isEmpty)
    }

    func testBothAnswersToTheInterruptionCardAreWrittenDown() async {
        let waited = await busySecretary()
        waited.submit("and another thing")
        waited.resolveInterruption(.wait)
        XCTAssertTrue(waited.transcript.contains { $0.text.contains(chosenLine(CardChoice.waitItsTurn)) })

        let replaced = await busySecretary()
        replaced.submit("actually do this instead")
        provider.eventsForNextTurn = [.completed(stopReason: .none(), usage: .none())]
        replaced.resolveInterruption(.replace)
        await waitUntilIdle()
        XCTAssertTrue(replaced.transcript.contains { $0.text.contains(chosenLine(CardChoice.replaceRunning)) })
    }

    func testStoppingLabelsTheHalfWrittenReplyAndOwnsUpToIt() async {
        let secretary = await busySecretary()
        secretary.stopCurrentTurn(because: "you stopped it")

        XCTAssertTrue(
            secretary.transcript.contains { $0.text.contains("stopped part-way") },
            "Got: \(secretary.transcript.map(\.text))"
        )
        XCTAssertFalse(machine.state.isBusy)

        provider.eventsForNextTurn = [
            .textDelta("ok"),
            .completed(stopReason: .none(), usage: .none())
        ]
        secretary.submit("carry on")
        await waitUntilIdle()
        XCTAssertTrue(
            provider.lastMessages.contains { $0.role == .assistant && $0.content.contains("working on it") },
            "Got: \(provider.lastMessages.map { "\($0.role): \($0.content)" })"
        )
    }

    func testAHeldQueueDoesNotStartWhenTheTurnEnds() async {
        let secretary = await busySecretary()
        secretary.submit("later, please")
        secretary.resolveInterruption(.wait)
        secretary.toggleQueuePause()

        secretary.stopCurrentTurn(because: "you stopped it")
        await waitUntilIdle()
        XCTAssertEqual(secretary.queuedMessages, ["later, please"], "held means held")
        XCTAssertEqual(provider.callCount, 1)

        provider.eventsForNextTurn = [
            .textDelta("ok"),
            .completed(stopReason: .none(), usage: .none())
        ]
        secretary.toggleQueuePause()
        await waitUntilIdle()
        XCTAssertTrue(secretary.queuedMessages.isEmpty, "letting go runs it")
        XCTAssertEqual(provider.callCount, 2)
    }

    func testTypingAgainInsteadOfAnsweringKeepsTheMessage() async {
        let secretary = await busySecretary()
        secretary.submit("first extra")
        secretary.submit("second extra")

        XCTAssertEqual(secretary.queuedMessages, ["first extra"])
        guard case .interruption(let text, _, _) = secretary.pendingDecision.toOptional() else {
            return XCTFail("the newest one is the question now")
        }
        XCTAssertEqual(text, "second extra")
    }

    func testNewConversationForgetsTheContextAndStopsWhatWasStanding() async {
        let secretary = await busySecretary()
        secretary.submit("something for later")
        secretary.resolveInterruption(.wait)
        XCTAssertEqual(secretary.queuedMessages.count, 1)

        secretary.newConversation()

        XCTAssertTrue(secretary.queuedMessages.isEmpty, "nothing waiting survives")
        XCTAssertFalse(secretary.queuePaused)
        XCTAssertFalse(machine.state.isBusy, "and nothing is still running")

        provider.eventsForNextTurn = [
            .textDelta("ok"),
            .completed(stopReason: .none(), usage: .none())
        ]
        secretary.submit("a fresh question")
        await waitUntilIdle()
        XCTAssertFalse(
            provider.lastMessages.contains { $0.content.contains("the first thing") },
            "the old thread must not follow it. Got: \(provider.lastMessages.map(\.content))"
        )
    }

    func testNewConversationClearsTheScreenAndKeepsWhatWasOnIt() async {
        let secretary = await busySecretary()

        secretary.newConversation()

        XCTAssertFalse(
            secretary.transcript.contains { $0.text.contains("the first thing") },
            "the screen belongs to the new conversation"
        )
        XCTAssertTrue(
            secretary.transcript.contains { $0.kind == .divider },
            "the line has to be findable, not just words that look like one"
        )
        XCTAssertTrue(
            secretary.history.first?.entries.contains { $0.text.contains("the first thing") } == true,
            "and what was said is still reachable. Got: \(secretary.history.map(\.title))"
        )
    }

    func testClearingTheQueueDropsItRatherThanHoldingIt() async {
        let secretary = await busySecretary()
        secretary.submit("never mind this one")
        secretary.resolveInterruption(.wait)

        secretary.clearQueue()

        XCTAssertTrue(secretary.queuedMessages.isEmpty)
        XCTAssertTrue(
            secretary.transcript.contains { $0.text.contains("Dropped 1 message") },
            "a queue disappearing quietly reads the same as one that ran"
        )
    }

    func testAToolBetweenTwoSentencesSplitsThemIntoTwoBubbles() async {
        let secretary = makeSecretary(projects: [
            Project(name: "Second-Brain", path: "/tmp/second-brain", allowedTools: [Secretary.claudeCodeToolID])
        ])
        provider.eventsForNextTurn = [
            .textDelta("Type /grill-with-docs yourself."),
            .activity(AgentActivity(kind: .tool, detail: "Read notes.md")),
            .textDelta("No existing note on this, so I'll capture it."),
            .activity(AgentActivity(kind: .tool, detail: "Write notes.md")),
            .textDelta("Saved, and the daily note is updated."),
            .completed(stopReason: .none(), usage: .none())
        ]

        secretary.submit("do the thing")
        await waitUntilIdle()

        let said = secretary.transcript
            .filter { $0.speaker == .secretary && $0.kind != .activity }
            .map(\.text)
            .filter { !$0.isEmpty }
        XCTAssertEqual(said.count, 3, "one bubble per stretch of talking. Got: \(said)")
        XCTAssertEqual(said.first, "Type /grill-with-docs yourself.")
        XCTAssertEqual(said.last, "Saved, and the daily note is updated.")
        XCTAssertFalse(
            said.contains { $0.contains("yourself.No existing") },
            "the seam is the whole point"
        )
    }

    func testTheSplitIsOnlyOnScreen() async {
        let secretary = makeSecretary(projects: [
            Project(name: "Second-Brain", path: "/tmp/second-brain", allowedTools: [Secretary.claudeCodeToolID])
        ])
        provider.eventsForNextTurn = [
            .textDelta("First half."),
            .activity(AgentActivity(kind: .tool, detail: "Read x")),
            .textDelta(" Second half."),
            .completed(stopReason: .none(), usage: .none())
        ]

        secretary.submit("go")
        await waitUntilIdle()
        provider.replyForNextTurn = "ok"
        secretary.submit("and again")
        await waitUntilIdle()

        let assistantTurns = provider.lastMessages.filter { $0.role == .assistant }
        XCTAssertTrue(
            assistantTurns.contains { $0.content == "First half. Second half." },
            "the model is told it said one thing. Got: \(assistantTurns.map(\.content))"
        )
    }

    func testTheBannerKeepsTheBubblesApart() async {
        let secretary = makeSecretary(projects: [
            Project(name: "Second-Brain", path: "/tmp/second-brain", allowedTools: [Secretary.claudeCodeToolID])
        ])
        var finished: [FinishedTurn] = []
        secretary.onTurnFinished = { finished.append($0) }
        provider.eventsForNextTurn = [
            .textDelta("done"),
            .activity(AgentActivity(kind: .tool, detail: "Read x")),
            .textDelta("Nothing to capture."),
            .completed(stopReason: .none(), usage: .none())
        ]

        secretary.submit("go")
        await waitUntilIdle()

        XCTAssertEqual(finished.last?.text, "done\n\nNothing to capture.")
        XCTAssertEqual(finished.last?.succeeded, true)
        XCTAssertEqual(finished.last?.wasErrand, false)
    }

    func testANewBlockOfTextIsANewBubbleEvenWithNoToolBetween() async {
        let secretary = makeSecretary(projects: [
            Project(name: "Second-Brain", path: "/tmp/second-brain", allowedTools: [Secretary.claudeCodeToolID])
        ])
        provider.eventsForNextTurn = [
            .textBlockBegan,
            .textDelta("The files are CLAUDE.md, Home.md, README.md"),
            .textBlockBegan,
            .textDelta("Nothing here worth capturing."),
            .completed(stopReason: .none(), usage: .none())
        ]

        secretary.submit("count them")
        await waitUntilIdle()

        let said = secretary.transcript
            .filter { $0.speaker == .secretary && $0.kind != .activity }
            .map(\.text)
            .filter { !$0.isEmpty }
        XCTAssertEqual(said.count, 2, "Got: \(said)")
        XCTAssertFalse(
            said.contains { $0.contains("README.mdNothing") },
            "this exact join is the bug"
        )
    }

    func testTheOpeningBlockBoundaryAddsNoBlankBubble() async {
        let secretary = makeSecretary(projects: [
            Project(name: "Second-Brain", path: "/tmp/second-brain", allowedTools: [Secretary.claudeCodeToolID])
        ])
        provider.eventsForNextTurn = [
            .textBlockBegan,
            .textDelta("Just the one thing."),
            .completed(stopReason: .none(), usage: .none())
        ]

        secretary.submit("hi")
        await waitUntilIdle()

        let said = secretary.transcript.filter { $0.speaker == .secretary && $0.kind != .activity }
        XCTAssertEqual(said.count, 1, "Got: \(said.map(\.text))")
    }

    func testATurnThatStartsWithAToolGainsNoBlankBubble() async {
        let secretary = makeSecretary(projects: [
            Project(name: "Second-Brain", path: "/tmp/second-brain", allowedTools: [Secretary.claudeCodeToolID])
        ])
        provider.eventsForNextTurn = [
            .activity(AgentActivity(kind: .tool, detail: "Read x")),
            .textDelta("Only one thing said."),
            .completed(stopReason: .none(), usage: .none())
        ]

        secretary.submit("go")
        await waitUntilIdle()

        let said = secretary.transcript.filter { $0.speaker == .secretary && $0.kind != .activity }
        XCTAssertEqual(said.count, 1, "Got: \(said.map(\.text))")
        XCTAssertEqual(said.first?.text, "Only one thing said.")
    }
}

final class ProjectGrantTests: XCTestCase {
    func testGrantAddsTheToolAndPersistsIt() throws {
        let project = Project(name: "P", path: "/tmp/p", allowedTools: ["a"])
        let store = InMemoryProjectStore(projects: [project])
        let registry = ProjectRegistry(store: store)

        XCTAssertTrue(registry.grant(tool: "b", to: project.id).getOrElse(false))
        XCTAssertEqual(store.load().getOrElse([]).first?.allowedTools, ["a", "b"])
    }

    func testGrantingTwiceIsANoOp() throws {
        let project = Project(name: "P", path: "/tmp/p", allowedTools: ["a"])
        let store = InMemoryProjectStore(projects: [project])
        let registry = ProjectRegistry(store: store)

        XCTAssertTrue(registry.grant(tool: "b", to: project.id).getOrElse(false))
        XCTAssertFalse(registry.grant(tool: "b", to: project.id).getOrElse(false))
        XCTAssertEqual(store.load().getOrElse([]).first?.allowedTools, ["a", "b"])
    }

    func testGrantingToAnUnknownProjectDoesNothing() throws {
        let registry = ProjectRegistry(store: InMemoryProjectStore(projects: []))
        XCTAssertFalse(registry.grant(tool: "b", to: UUID()).getOrElse(false))
    }
}
