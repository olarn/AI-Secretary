import FunctionalCore
import XCTest
import AssistantState
import Permissions
import ProjectRegistry
import ToolAdapters
@testable import SecretaryCore

@MainActor
final class OfferedAnswersTests: XCTestCase {
    private let project = Project(
        name: "Fixture",
        path: "/tmp/fixture",
        allowedTools: [GitReadOnlyAdapter.toolIdentifier]
    )

    private func makeSecretary(registered: [Project]) -> Secretary {
        Secretary(
            stateMachine: AssistantStateMachine(),
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: registered)),
            adapter: SpyAdapter(),
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: FakeChatProvider(.events([]))
        )
    }

    func testNothingWaitingOffersNothing() {
        XCTAssertEqual(makeSecretary(registered: [project]).offeredApprovalAnswers, [])
    }

    func testReadingARegisteredProjectOffersAllThree() async {
        let secretary = makeSecretary(registered: [project])
        secretary.submit("git status in Fixture")
        await settle(secretary)

        XCTAssertEqual(secretary.offeredApprovalAnswers, [.once, .always, .deny])
    }

    func testAFolderOutsideAnyProjectOffersOnlyOnceAndDeny() async throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let secretary = makeSecretary(registered: [project])
        secretary.submit("/watch \(outside.path)")
        await settle(secretary)

        guard !secretary.offeredApprovalAnswers.isEmpty else {
            return XCTFail("expected a card, got: \(secretary.transcript.last?.text ?? "-")")
        }
        XCTAssertEqual(secretary.offeredApprovalAnswers, [.once, .deny])
    }

    private func settle(_ secretary: Secretary, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while secretary.pendingDecision == .none(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
