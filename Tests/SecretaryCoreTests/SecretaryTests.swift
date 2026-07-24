import XCTest
import AssistantState
import ProjectRegistry
import Permissions
import ToolAdapters
@testable import SecretaryCore

// MARK: - Test doubles

final class SpyAdapter: CodeToolAdapter {
    var toolID: String { GitReadOnlyAdapter.toolIdentifier }
    private(set) var runCalls: [(CodeToolOperation, Project)] = []
    var stubbedResult: ToolResult = ToolResult(output: "ok", exitCode: 0, commandSummary: "git status")
    var stubbedError: Error?

    func summary(for operation: CodeToolOperation) -> String { "git \(operation.rawValue)" }

    func run(_ operation: CodeToolOperation, in project: Project) throws -> ToolResult {
        runCalls.append((operation, project))
        if let stubbedError { throw stubbedError }
        return stubbedResult
    }
}

// MARK: - Intent classification

final class RuleBasedIntentClassifierTests: XCTestCase {
    private let classifier = RuleBasedIntentClassifier()

    func testRecognisesEachSupportedOperation() {
        let cases: [(String, CodeToolOperation)] = [
            ("git status", .status),
            ("show me the diff", .diffStat),
            ("what are the recent commits", .recentLog),
            ("which branch am I on", .currentBranch)
        ]

        for (text, expected) in cases {
            guard case .codeTool(let operation, _) = classifier.classify(text) else {
                return XCTFail("Expected codeTool for “\(text)”")
            }
            XCTAssertEqual(operation, expected, "for “\(text)”")
        }
    }

    func testExtractsProjectNameAfterIn() {
        guard case .codeTool(_, let query) = classifier.classify("git status in AI-Secretary") else {
            return XCTFail("Expected codeTool")
        }
        XCTAssertEqual(query, "ai-secretary")
    }

    func testNoProjectPhraseYieldsNilQuery() {
        guard case .codeTool(_, let query) = classifier.classify("git status") else {
            return XCTFail("Expected codeTool")
        }
        XCTAssertNil(query)
    }

    func testUnrecognisedTextIsUnknownRatherThanAGuess() {
        for text in ["delete everything", "rm -rf /", "make me a sandwich", ""] {
            guard case .unknown = classifier.classify(text) else {
                return XCTFail("“\(text)” must classify as unknown")
            }
        }
    }

    func testHelpIsRecognised() {
        XCTAssertEqual(classifier.classify("help"), .help)
    }
}

// MARK: - Orchestration

final class SecretaryTests: XCTestCase {
    private var machine: AssistantStateMachine!
    private var adapter: SpyAdapter!
    private var policy: DefaultPermissionPolicy!

    private let project = Project(
        name: "Fixture",
        path: "/tmp/fixture",
        allowedTools: [GitReadOnlyAdapter.toolIdentifier]
    )

    override func setUp() {
        super.setUp()
        machine = AssistantStateMachine()
        adapter = SpyAdapter()
        policy = DefaultPermissionPolicy()
    }

    private func makeSecretary(projects: [Project]) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: projects)),
            policy: policy,
            adapter: adapter,
            classifier: RuleBasedIntentClassifier(),
            audit: AuditLog()
        )
    }

    func testFirstRequestAsksForApprovalAndRunsNothingYet() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")

        guard case .approval(let request, _) = secretary.pendingDecision else {
            return XCTFail("Expected an approval prompt, got \(String(describing: secretary.pendingDecision))")
        }
        XCTAssertEqual(request.project, project)
        XCTAssertTrue(adapter.runCalls.isEmpty, "Nothing may run before approval")
    }

    func testGrantingApprovalRunsTheToolAndReportsSuccess() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        XCTAssertEqual(adapter.runCalls.count, 1)
        XCTAssertEqual(adapter.runCalls.first?.0, .status)
        XCTAssertEqual(machine.state, .idle, "Task should complete back to idle")
        XCTAssertTrue(secretary.transcript.last?.text.contains("ok") ?? false)
    }

    func testDenyingApprovalRunsNothing() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: false)

        XCTAssertTrue(adapter.runCalls.isEmpty)
        XCTAssertNil(secretary.pendingDecision)
        XCTAssertEqual(machine.state, .idle)
    }

    func testSecondRequestSkipsApprovalForTheSameProjectAndTool() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        secretary.submit("git status")

        XCTAssertNil(secretary.pendingDecision, "Approved project/tool should not re-prompt")
        XCTAssertEqual(adapter.runCalls.count, 2)
    }

    func testUnknownProjectNameNeverRunsAnything() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status in nonexistent-project")

        XCTAssertTrue(adapter.runCalls.isEmpty)
        XCTAssertNil(secretary.pendingDecision)
        XCTAssertTrue(secretary.transcript.last?.text.contains("No registered project") ?? false)
    }

    func testAmbiguousProjectAsksUserToChooseBeforeRunning() {
        let a = Project(name: "Alpha", path: "/tmp/a", allowedTools: [GitReadOnlyAdapter.toolIdentifier])
        let b = Project(name: "AlphaBeta", path: "/tmp/b", allowedTools: [GitReadOnlyAdapter.toolIdentifier])
        let secretary = makeSecretary(projects: [a, b])

        secretary.submit("git status in alph")

        guard case .projectChoice(let candidates, _) = secretary.pendingDecision else {
            return XCTFail("Expected a project choice prompt")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(adapter.runCalls.isEmpty)
    }

    func testChoosingAProjectContinuesIntoApproval() {
        let a = Project(name: "Alpha", path: "/tmp/a", allowedTools: [GitReadOnlyAdapter.toolIdentifier])
        let b = Project(name: "AlphaBeta", path: "/tmp/b", allowedTools: [GitReadOnlyAdapter.toolIdentifier])
        let secretary = makeSecretary(projects: [a, b])

        secretary.submit("git status in alph")
        secretary.choose(project: b)

        guard case .approval(let request, _) = secretary.pendingDecision else {
            return XCTFail("Expected approval after choosing a project")
        }
        XCTAssertEqual(request.project, b)
    }

    func testToolNotAllowlistedOnProjectIsDeniedWithoutPrompting() {
        let locked = Project(name: "Locked", path: "/tmp/locked", allowedTools: [])
        let secretary = makeSecretary(projects: [locked])

        secretary.submit("git status")

        XCTAssertNil(secretary.pendingDecision, "A denial must not offer an approval prompt")
        XCTAssertTrue(adapter.runCalls.isEmpty)
        XCTAssertTrue(secretary.transcript.last?.text.contains("not in the allowlist") ?? false)
    }

    func testUnknownIntentRunsNothingAndEndsInIdle() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("please delete the database")

        XCTAssertTrue(adapter.runCalls.isEmpty)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(secretary.transcript.last?.text.contains("didn't understand") ?? false)
    }

    func testAdapterFailureIsReportedWithoutCrashing() {
        let secretary = makeSecretary(projects: [project])
        adapter.stubbedError = ToolError.notAGitRepository("/tmp/fixture")

        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(secretary.transcript.last?.text.contains("Not a Git repository") ?? false)
    }

    func testNonZeroExitIsReportedAsFailure() {
        let secretary = makeSecretary(projects: [project])
        adapter.stubbedResult = ToolResult(output: "fatal", exitCode: 128, commandSummary: "git status")

        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        XCTAssertTrue(secretary.transcript.last?.text.contains("128") ?? false)
        XCTAssertEqual(machine.state, .idle)
    }

    func testAuditTrailCoversTheWholeApprovedRun() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        let kinds = secretary.auditEntries.map(\.kind)
        XCTAssertEqual(
            kinds,
            [.requestReceived, .intentClassified, .projectResolved,
             .approvalRequested, .approvalGranted, .executionStarted, .executionFinished]
        )

        let taskIDs = Set(secretary.auditEntries.map(\.taskID))
        XCTAssertEqual(taskIDs.count, 1, "All entries for one request share a correlation ID")
    }

    func testStateMachineWalksTheFullLifecycleForAnApprovedRun() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(granted: true)

        XCTAssertEqual(
            machine.history.map(\.to),
            [.listening, .thinking, .working, .success, .idle]
        )
    }
}
