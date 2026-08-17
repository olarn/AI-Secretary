import FunctionalCore
import XCTest
import AssistantState
import Permissions
import ProjectRegistry
import ToolAdapters
@testable import SecretaryCore

/// The half of Sprint 15 that survives quitting: what reaches the file, what is
/// read back, and what a new session does with it.
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

    /// A new conversation in the same project does not ask again — the sentence
    /// the sprint item opens with.
    func testWhatWasRememberedIsInForceOnTheNextLaunch() {
        let store = InMemoryStandingGrantStore(grants: [
            StandingGrant(
                projectID: project.id,
                toolID: GitReadOnlyAdapter.toolIdentifier,
                actionClass: .readOnly
            )
        ])
        let secretary = makeSecretary(store: store)

        XCTAssertTrue(
            secretary.grants.has(
                projectID: project.id,
                toolID: GitReadOnlyAdapter.toolIdentifier,
                actionClass: .readOnly
            )
        )
    }

    /// Starting with nothing on file is the ordinary case and must not look
    /// like a grant.
    func testAnEmptyStoreGrantsNothing() {
        let secretary = makeSecretary(store: InMemoryStandingGrantStore())
        XCTAssertTrue(secretary.grants.remembered.isEmpty)
    }

    /// A file that cannot be read starts the app with nothing remembered rather
    /// than refusing to start — and, more importantly, rather than guessing.
    func testAnUnreadableStoreIsTreatedAsNothingRemembered() {
        let secretary = makeSecretary(store: FailingGrantStore())
        XCTAssertTrue(secretary.grants.remembered.isEmpty)
    }

    // MARK: - The file itself

    func testTheFileRoundTripsAGrant() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grants-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileStandingGrantStore(fileURL: url)
        let written = [
            StandingGrant(projectID: project.id, toolID: "git.readOnly", actionClass: .localWrite)
        ]

        XCTAssertTrue(store.save(written).isRight)
        XCTAssertEqual(store.load().getOrElse([]), written)
    }

    /// No file yet is not a failure — it is the first launch.
    func testAMissingFileLoadsAsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString).json")
        XCTAssertEqual(FileStandingGrantStore(fileURL: url).load().getOrElse([.init(projectID: UUID(), toolID: "x", actionClass: .readOnly)]), [])
    }

    /// One file per character, so approving something for one is not approving
    /// it for everyone.
    func testEachCharacterHasHerOwnFile() {
        let one = FileStandingGrantStore.url(forCharacter: UUID())
        let other = FileStandingGrantStore.url(forCharacter: UUID())
        XCTAssertNotEqual(one, other)
        XCTAssertTrue(one.lastPathComponent.hasPrefix("permissions-"))
    }
}

/// A store that cannot be read, for the launch path that has to survive it.
private final class FailingGrantStore: StandingGrantStoring, @unchecked Sendable {
    func load() -> Either<GrantStoreError, [StandingGrant]> {
        .left(.readFailed(path: "/nowhere", message: "no"))
    }

    func save(_ grants: [StandingGrant]) -> Either<GrantStoreError, Void> {
        .left(.writeFailed(path: "/nowhere", message: "no"))
    }
}
