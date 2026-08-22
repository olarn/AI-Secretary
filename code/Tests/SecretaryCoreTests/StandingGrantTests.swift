import FunctionalCore
import XCTest
import AssistantState
import Permissions
import ProjectRegistry
import ToolAdapters
@testable import SecretaryCore

@MainActor
final class StandingGrantTests: XCTestCase {
    private let project = Project(
        name: "Fixture",
        path: "/tmp/fixture",
        allowedTools: [GitReadOnlyAdapter.toolIdentifier]
    )

    private func makeSecretary(store: StandingGrantStoring) -> Secretary {
        Secretary(
            stateMachine: AssistantStateMachine(),
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [project])),
            adapter: SpyAdapter(),
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: FakeChatProvider(.events([])),
            grantStore: store
        )
    }

    func testWhatWasRememberedIsInForceOnTheNextLaunch() {
        let store = InMemoryStandingGrantStore(grants: [
            StandingGrant(project: project)
        ])
        let secretary = makeSecretary(store: store)

        XCTAssertTrue(
            secretary.grants.has(
                project: project,
                toolID: GitReadOnlyAdapter.toolIdentifier,
                actionClass: .readOnly
            )
        )
    }

    func testAnEmptyStoreGrantsNothing() {
        let secretary = makeSecretary(store: InMemoryStandingGrantStore())
        XCTAssertTrue(secretary.grants.remembered.isEmpty)
    }

    func testAnUnreadableStoreIsTreatedAsNothingRemembered() {
        let secretary = makeSecretary(store: FailingGrantStore())
        XCTAssertTrue(secretary.grants.remembered.isEmpty)
    }

    func testTheFileRoundTripsAGrant() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grants-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileStandingGrantStore(fileURL: url)
        let written = [
            StandingGrant(project: project)
        ]

        XCTAssertTrue(store.save(written).isRight)
        XCTAssertEqual(store.load().getOrElse([]), written)
    }

    func testAMissingFileLoadsAsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString).json")
        XCTAssertEqual(
            FileStandingGrantStore(fileURL: url)
                .load()
                .getOrElse([StandingGrant(projectPath: CanonicalPath("/x"))]),
            []
        )
    }

    func testEachCharacterHasHerOwnFile() {
        let one = FileStandingGrantStore.url(forCharacter: UUID())
        let other = FileStandingGrantStore.url(forCharacter: UUID())
        XCTAssertNotEqual(one, other)
        XCTAssertTrue(one.lastPathComponent.hasPrefix("permissions-"))
    }
}

private final class FailingGrantStore: StandingGrantStoring, @unchecked Sendable {
    func load() -> Either<GrantStoreError, [StandingGrant]> {
        .left(.readFailed(path: "/nowhere", message: "no"))
    }

    func save(_ grants: [StandingGrant]) -> Either<GrantStoreError, Void> {
        .left(.writeFailed(path: "/nowhere", message: "no"))
    }
}
