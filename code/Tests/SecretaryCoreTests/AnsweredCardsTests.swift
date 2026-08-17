import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import Permissions
import ProjectRegistry
import ToolAdapters
@testable import SecretaryCore

/// The wording of a record, on its own.
final class CardChoiceTests: XCTestCase {

    func testAChoiceIsNamedInTheChoosersOwnWords() {
        XCTAssertEqual(chosenLine("Always"), "You chose “Always”")
    }

    /// The whole point of `CardChoice` existing in a library target. If a button
    /// title is ever retyped in the view instead of read from here, the record
    /// and the button drift apart and no test in `AISecretaryApp` can see it —
    /// that target is never linked into the test bundle.
    func testEveryCardTitleIsSomethingATestCanRead() {
        let titles = [
            CardChoice.waitItsTurn, CardChoice.replaceRunning,
            CardChoice.goAhead, CardChoice.notThisOne,
            CardChoice.start, CardChoice.cancel,
        ] + PermissionAnswer.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "Two cards must not share a title")
        XCTAssertFalse(titles.contains { $0.isEmpty })
    }
}

/// The badge beside her name.
final class ModelBadgeTests: XCTestCase {

    func testTheMakersNameIsDropped() {
        XCTAssertEqual(shortModelName("Claude Opus 5"), "Opus 5")
        XCTAssertEqual(shortModelName("Claude Sonnet 5"), "Sonnet 5")
    }

    /// Not every name starts that way — `inheritedSettingName` doesn't — and
    /// chopping seven characters off one that doesn't would produce "ult".
    func testANameWithoutThePrefixIsLeftAlone() {
        XCTAssertEqual(shortModelName("Default"), "Default")
        XCTAssertEqual(shortModelName("Opus 5"), "Opus 5")
    }

    func testTheBadgeNamesBothHalves() {
        XCTAssertEqual(modelBadge(model: "Claude Opus 5", effort: "medium"), "Opus 5 | medium")
    }

    /// The case the collapse exists for: "Default | Default" reads as two
    /// settings that happen to agree, when it means the app was told neither.
    func testKnowingNeitherIsOneWordNotTwo() {
        XCTAssertEqual(modelBadge(model: "Default", effort: "Default"), "Default")
    }

    func testKnowingOneOfThemStillShowsBoth() {
        XCTAssertEqual(modelBadge(model: "Claude Opus 5", effort: "Default"), "Opus 5 | Default")
        XCTAssertEqual(modelBadge(model: "Default", effort: "high"), "Default | high")
    }
}

/// Answering a card leaves a record of the answer.
///
/// The bug these pin: a card vanishes the instant it is answered, and for
/// approving, for picking a project and for replacing a running turn nothing
/// was said afterwards that named the answer — so scrolling back showed a
/// question, then whatever happened next, with no sign that anyone had replied.
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

    // MARK: - Approval

    func testApprovingOnceIsWrittenDown() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.resolvePendingApproval(answer: .once)

        XCTAssertTrue(said(secretary, chosenLine("Once")), "No record of the answer")
        XCTAssertTrue(said(secretary, "just this time"))
    }

    /// The line has to say the grant was kept, because that is the half of the
    /// answer the person cannot see anywhere else — nothing on screen afterwards
    /// distinguishes a session grant from a standing one.
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

    /// The record goes in front of the work, not behind it. An answer reported
    /// underneath its own consequences reads as the app narrating itself after
    /// the fact rather than as the person having replied.
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

    // MARK: - Choosing a project

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

    // MARK: - Cancelling

    func testCancellingNamesTheButtonThatWasPressed() {
        let secretary = makeSecretary(projects: [project])
        secretary.submit("git status")
        secretary.cancelPendingDecision()

        XCTAssertTrue(said(secretary, chosenLine("Cancel")))
    }
}
