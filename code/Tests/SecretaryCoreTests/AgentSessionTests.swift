import FunctionalCore
import XCTest
import AssistantState
import ProjectRegistry
import Permissions
import ToolAdapters
import LLMProvider
@testable import SecretaryCore

/// A chat provider that is also directory-scoped, so we can see what the
/// Secretary told it before a turn.
final class SpyWorkspaceProvider: ChatProvider, WorkspaceScopedProvider, @unchecked Sendable {
    private(set) var preparedDirectories: [URL?] = []
    private(set) var preparedTools: [[String]?] = []
    private(set) var callCount = 0
    private(set) var lastMessages: [ChatMessage] = []
    private(set) var lastSystem: String?
    private(set) var lastModel: ChatModel?
    private(set) var resetCount = 0
    var hasWorkspaceTools = true
    /// Refusals to emit on the next turn, then cleared — so a retry succeeds.
    var denialsForNextTurn: [DeniedTool] = []
    var activityForNextTurn: [AgentActivity] = []
    /// Scripted text for the next turn, then cleared.
    var replyForNextTurn: String?

    private(set) var preparedExtras: [[URL]] = []

    func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?) {
        preparedDirectories.append(workingDirectory)
        preparedExtras.append(additionalDirectories)
        preparedTools.append(allowedTools)
    }

    func resetConversation() { resetCount += 1 }

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

    private func makeSecretary(projects: [Project]) -> Secretary {
        store = InMemoryProjectStore(projects: projects)
        registry = ProjectRegistry(store: store)
        return Secretary(
            stateMachine: machine,
            registry: registry,
            adapter: SpyAdapter(),
            fileAdapter: SpyFileAdapter(),
            classifier: RuleBasedIntentClassifier(),
            audit: AuditLog(),
            activityPreference: activityPreference,
            chatProvider: provider
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

    // MARK: - Asking before working in a project

    func testFirstMessageInAnUngrantedProjectAsksBeforeRunningAnything() {
        let secretary = makeSecretary(projects: [project(grantingAgent: false)])
        secretary.submit("what does this project do?")

        guard case .approval(let request, let operation) = secretary.pendingDecision else {
            return XCTFail("Expected an approval request")
        }
        XCTAssertEqual(request.toolID, Secretary.claudeCodeToolID)
        XCTAssertEqual(operation, .startAgent(prompt: "what does this project do?"))
        XCTAssertEqual(provider.callCount, 0, "Nothing may run before approval")
        XCTAssertTrue(provider.preparedDirectories.isEmpty)
    }

    /// The prompt has to say what the grant actually covers, because it is
    /// approve-once rather than per-message.
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

        XCTAssertNil(secretary.pendingDecision)
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

        XCTAssertNil(secretary.pendingDecision, "The second message must not ask again")
        XCTAssertEqual(provider.callCount, 2)
    }

    // MARK: - Telling the backend what it can do

    /// Reported from real use: asked to summarise a project, the assistant said
    /// it couldn't see the contents and asked the user to paste them, then told
    /// them to type `list files in <project>`. The system prompt was the
    /// chat-only one, which says the model cannot run commands itself.
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

    /// Every marker block the app can act on has to be described in the prompt
    /// the backend actually receives.
    ///
    /// This exists because it wasn't. The loop and window blocks were written
    /// into `capabilityPrompt`, which only the API-key path uses, while Claude
    /// Code — the backend this app really runs on — got `agentPrompt`, which
    /// mentioned neither. The parsers were right and every test passed, and the
    /// assistant answered "no window tool is available to me in this session",
    /// because as far as it knew there wasn't one.
    func testTheAgentPromptDescribesEveryMarkerBlockTheAppUnderstands() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        let prompt = provider.lastSystem ?? "-"
        for fence in [MessageChoices.fence, LoopBlock.fence, InfoWindowBlock.fence] {
            XCTAssertTrue(prompt.contains(fence), "\(fence) is not described. Got: \(prompt)")
        }
    }

    /// From a real conversation: asked for a ratebook and to pin it, the
    /// assistant said the folder was empty; told "from the project's MCP", it
    /// tried the server, reported that it worked, and searched for a different
    /// car in a different year — never answering the question or pinning
    /// anything. It read the second message as a fresh instruction instead of
    /// as the missing piece of the first.
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
        for fence in [LoopBlock.fence, InfoWindowBlock.fence] {
            XCTAssertTrue(prompt.contains(fence), "\(fence) is not described. Got: \(prompt)")
        }
    }

    /// Adding a project mid-conversation is a correction, so the question that
    /// prompted it gets asked again on the newly scoped workspace. Without this
    /// the registry gained a folder and nothing else happened at all.
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

    /// Nothing to resume, nothing to do — and no empty turn sent.
    func testAddingAProjectWithNoConversationAsksNothing() async {
        let secretary = makeSecretary(projects: [])
        let before = provider.callCount
        secretary.projectsDidChange()
        await waitUntilIdle()
        XCTAssertEqual(provider.callCount, before)
    }

    /// The whole point: after a blocked turn the next prompt carries the
    /// request itself, not just a general rule about missing pieces.
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

    /// A turn that finished clears it, so the reminder can't haunt the rest of
    /// the conversation.
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

    /// The old prompt is still right for a plain chat model with no tools.
    func testAChatOnlyBackendKeepsTheAdviceToTypeCommands() async {
        provider.hasWorkspaceTools = false
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertTrue(provider.lastSystem?.contains("cannot run commands") == true,
                      "Got: \(provider.lastSystem ?? "-")")
    }

    // MARK: - Widening permissions after a refusal

    private func denyWrite() -> DeniedTool {
        DeniedTool(name: "Write", target: .some("/tmp/agent-fixture/out.txt"), rule: "Write")
    }

    /// Claude Code refuses un-granted tools mid-turn rather than asking, so the
    /// only way to widen is to notice the refusal and offer a retry.
    func testARefusedToolOffersToAllowItAndTryAgain() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        provider.denialsForNextTurn = [denyWrite()]
        secretary.submit("create out.txt")
        await waitUntilIdle()

        guard case .approval(let request, let operation) = secretary.pendingDecision else {
            return XCTFail("Expected an offer to widen, got: \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(operation, .widenAgentTools(rules: ["Write"], prompt: "create out.txt"))
        XCTAssertEqual(request.actionClass, .localWrite, "Writing files must never be approve-once")
        XCTAssertTrue(secretary.transcript.contains { $0.text.contains("out.txt") },
                      "The prompt should say what was blocked")
    }

    /// The previous turn ended at IDLE, so the retry has to re-enter the state
    /// machine properly — otherwise the character sits still through it and any
    /// caller waiting on "busy then idle" is misled.
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

    /// Read access to a project persists; permission to change files must not.
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
            DeniedTool(name: "Bash", target: .some("npm test"), rule: "Bash(npm test *)"),
            denyWrite()
        ]
        secretary.submit("set the project up")
        await waitUntilIdle()

        guard case .approval(_, let operation) = secretary.pendingDecision,
              case .widenAgentTools(let rules, _) = operation else {
            return XCTFail("Expected one combined offer")
        }
        XCTAssertEqual(rules, ["Write", "Bash(npm test *)"], "Duplicates should collapse")
    }

    func testATurnWithNoRefusalsAsksNothing() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.submit("just tell me about it")
        await waitUntilIdle()

        XCTAssertNil(secretary.pendingDecision)
    }

    // MARK: - Choosing a model from the settings panel

    /// A change made in the panel takes effect in the conversation, so it is
    /// announced there — the same path the slash command uses.
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
        XCTAssertTrue(secretary.transcript.last?.text.contains("Claude Code default") == true,
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

    /// The chosen value must reach the backend, not just the label.
    func testAPickedModelIsUsedForTheNextTurn() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        secretary.selectModel(.some(.fable5))
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertEqual(provider.lastModel, .fable5)
    }

    // MARK: - Showing what it's doing

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

    /// Several thinking blocks in a row are one thing happening, not five.
    func testRepeatedIdenticalStepsCollapse() async {
        let secretary = makeSecretary(projects: [project(grantingAgent: true)])
        let thinking = AgentActivity(kind: .thinking, detail: "Thinking")
        provider.activityForNextTurn = [thinking, thinking, thinking]
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertEqual(secretary.activity.count, 1)
    }

    /// It belongs in the conversation, in order, ahead of the answer it
    /// preceded — and marked as not being the answer.
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

    /// The change is announced in the same dashed-box style as activity itself
    /// — it's a status change, not something she's saying — and turning off
    /// clears the boxes from earlier in the turn, leaving only the announcement.
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

    /// A first run is quiet; the choice is remembered after that.
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
        // A relaunch reads it back.
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
        // The toggle-off announcement itself is the one .activity entry so far;
        // what must NOT happen is a second one for this turn's steps.
        let countAfterToggle = secretary.transcript.filter { $0.kind == .activity }.count

        provider.activityForNextTurn = [AgentActivity(kind: .tool, detail: "Read: a.md")]
        secretary.submit("hello")
        await waitUntilIdle()

        XCTAssertEqual(secretary.transcript.filter { $0.kind == .activity }.count, countAfterToggle,
                       "No box should be added for this turn's steps while hidden")
        XCTAssertFalse(secretary.activity.isEmpty, "Still collected, just not shown")
    }

    /// Each turn gets its own box. Matching by kind alone would find the
    /// previous turn's and rewrite that history with the current steps.
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

    /// A new question starts a fresh list — last turn's steps aren't current.
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

    // MARK: - Working with no project

    /// Claude Code always runs somewhere. With no project registered it must not
    /// inherit whatever directory the app launched from.
    func testWithNoProjectItRunsInAScratchDirectoryNotTheLaunchDirectory() async {
        let secretary = makeSecretary(projects: [])
        secretary.submit("hello")
        await waitUntilIdle()

        let directory = try? XCTUnwrap(provider.preparedDirectories.last ?? nil)
        XCTAssertEqual(directory?.lastPathComponent, "scratch")
        XCTAssertNotEqual(directory?.path, FileManager.default.currentDirectoryPath)
        XCTAssertEqual(provider.callCount, 1)
    }

    // MARK: - More than one project

    /// The point of the feature: with two approved projects, both are reachable
    /// in one turn so a question spanning them doesn't need the user to switch.
    func testEveryApprovedProjectIsOpenAlongsideThePrimaryOne() async {
        let other = Project(name: "Other", path: "/tmp/other",
                            allowedTools: [Secretary.claudeCodeToolID])
        let secretary = makeSecretary(projects: [project(grantingAgent: true), other])
        secretary.submit("compare the two projects")
        await waitUntilIdle()

        XCTAssertEqual(provider.preparedDirectories.last??.path, projectPath)
        XCTAssertEqual(provider.preparedExtras.last?.map(\.path), ["/tmp/other"])
    }

    /// Only approved folders may be opened — the per-project grant is the gate.
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

    /// Several projects, none approved yet: guessing would be wrong, so ask.
    func testSeveralUnapprovedProjectsAskWhichToStartIn() {
        let secretary = makeSecretary(projects: [
            project(grantingAgent: false),
            Project(name: "Other", path: "/tmp/other", allowedTools: [])
        ])
        secretary.submit("hello")

        guard case .projectChoice(let candidates, let operation) = secretary.pendingDecision else {
            return XCTFail("Expected a project choice, got: \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(operation, .startAgent(prompt: "hello"))
        XCTAssertEqual(provider.callCount, 0)
    }

    /// Choosing an unapproved project still has to ask before running.
    func testChoosingAProjectThenAsksToApproveIt() {
        let secretary = makeSecretary(projects: [
            project(grantingAgent: false),
            Project(name: "Other", path: "/tmp/other", allowedTools: [])
        ])
        secretary.submit("hello")
        guard case .projectChoice(let candidates, _) = secretary.pendingDecision else {
            return XCTFail("Expected a project choice")
        }
        secretary.choose(project: candidates[0])

        guard case .approval(let request, _) = secretary.pendingDecision else {
            return XCTFail("Expected an approval request after choosing")
        }
        XCTAssertEqual(request.toolID, Secretary.claudeCodeToolID)
        XCTAssertEqual(provider.callCount, 0)
    }
}

// MARK: - Registry grants

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
