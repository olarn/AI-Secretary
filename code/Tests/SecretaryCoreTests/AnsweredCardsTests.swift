import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import Permissions
import ProjectRegistry
import ToolAdapters
@testable import SecretaryCore

final class CardChoiceTests: XCTestCase {

    func testAChoiceIsNamedInTheChoosersOwnWords() {
        XCTAssertEqual(chosenLine("Always"), "You chose “Always”")
    }

    func testEveryCardTitleIsSomethingATestCanRead() {
        let titles = [
            CardChoice.waitItsTurn, CardChoice.replaceRunning,
            CardChoice.goAhead, CardChoice.notThisOne,
            CardChoice.start, CardChoice.cancel,
            CardChoice.giveItToSomeone,
        ] + PermissionAnswer.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "Two cards must not share a title")
        XCTAssertFalse(titles.contains { $0.isEmpty })
    }
}

final class ModelBadgeTests: XCTestCase {

    func testTheMakersNameIsDropped() {
        XCTAssertEqual(shortModelName("Claude Opus 5"), "Opus 5")
        XCTAssertEqual(shortModelName("Claude Sonnet 5"), "Sonnet 5")
    }

    func testANameWithoutThePrefixIsLeftAlone() {
        XCTAssertEqual(shortModelName("Default"), "Default")
        XCTAssertEqual(shortModelName("Opus 5"), "Opus 5")
    }

    func testTheBadgeNamesBothHalves() {
        XCTAssertEqual(modelBadge(model: "Claude Opus 5", effort: "medium"), "Opus 5 | medium")
    }

    func testKnowingNeitherIsOneWordNotTwo() {
        XCTAssertEqual(modelBadge(model: "Default", effort: "Default"), "Default")
    }

    func testKnowingOneOfThemStillShowsBoth() {
        XCTAssertEqual(modelBadge(model: "Claude Opus 5", effort: "Default"), "Opus 5 | Default")
        XCTAssertEqual(modelBadge(model: "Default", effort: "high"), "Default | high")
    }
}

@MainActor
final class AnsweredCardsTests: XCTestCase {
    private var machine = AssistantStateMachine()
    private var adapter = SpyAdapter()

    private let project = Project(
        name: "Fixture",
        path: "/tmp/fixture",
        allowedTools: [GitReadOnlyAdapter.toolIdentifier]
    )

    override func setUp() {
        super.setUp()
        machine = AssistantStateMachine()
        adapter = SpyAdapter()
    }

    private func makeSecretary(projects: [Project]) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: projects)),
            adapter: adapter,
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: FakeChatProvider(.events([.completed(stopReason: .none(), usage: .none())]))
        )
    }

    private func said(_ secretary: Secretary, _ needle: String) -> Bool {
        secretary.transcript.contains { $0.text.contains(needle) }
    }

    func testApprovingOnceIsWrittenDown() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(answer: .once)

        XCTAssertTrue(said(secretary, chosenLine("Once")), "No record of the answer")
        XCTAssertTrue(said(secretary, "just this time"))
    }

    func testApprovingAlwaysSaysItWasKept() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(answer: .always)

        XCTAssertTrue(said(secretary, chosenLine("Always")))
        XCTAssertTrue(said(secretary, "I'll keep this for Fixture"))
    }

    func testDenyingNamesTheAnswerRatherThanJustSayingCancelled() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(answer: .deny)

        XCTAssertTrue(said(secretary, chosenLine("Deny")))
        XCTAssertTrue(adapter.runCalls.isEmpty)
    }

    func testTheAnswerIsRecordedBeforeTheResult() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(answer: .once)

        let answerAt = secretary.transcript.firstIndex { $0.text.contains(chosenLine("Once")) }
        let resultAt = secretary.transcript.lastIndex { $0.text.contains("ok") }
        XCTAssertNotNil(answerAt)
        XCTAssertNotNil(resultAt)
        XCTAssertLessThan(answerAt ?? 0, resultAt ?? 0)
    }

    func testChoosingAProjectIsWrittenDown() {
        let other = Project(
            name: "Second",
            path: "/tmp/second",
            allowedTools: [GitReadOnlyAdapter.toolIdentifier]
        )
        let secretary = makeSecretary(projects: [project, other])
        secretary.submit("git status")

        guard case .projectChoice? = secretary.pendingDecision.toOptional() else {
            return XCTFail("Expected the project card, got \(String(describing: secretary.pendingDecision.toOptional()))")
        }
        secretary.choose(project: other)
        XCTAssertTrue(said(secretary, chosenLine("Second")), "No record of which project was picked")
    }

    func testCancellingNamesTheButtonThatWasPressed() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.cancelPendingDecision()

        XCTAssertTrue(said(secretary, chosenLine("Cancel")))
    }
}
