import FunctionalCore
import XCTest
@testable import ProjectRegistry

private let alpha = Project(name: "Alpha", path: "/tmp/alpha", allowedTools: ["git.readOnly"])
private let alphaBeta = Project(name: "AlphaBeta", path: "/tmp/alphabeta")
private let gamma = Project(name: "Gamma", path: "/tmp/gamma")

/// Resolution is a pure function, so these need no registry object at all.
final class ResolveProjectTests: XCTestCase {
    private func resolve(_ projects: [Project], _ query: Option<String>) -> ProjectResolution {
        resolveProject(in: projects)(query)
    }

    func testExactNameResolvesEvenWhenAnotherNameContainsIt() {
        XCTAssertEqual(resolve([alpha, alphaBeta], .some("Alpha")), .resolved(alpha))
    }

    func testCaseInsensitiveAndTrimmedMatching() {
        XCTAssertEqual(resolve([alpha], .some("  aLpHa ")), .resolved(alpha))
    }

    func testPartialMatchResolvesWhenUnique() {
        XCTAssertEqual(resolve([alpha, gamma], .some("gam")), .resolved(gamma))
    }

    func testAmbiguousPartialMatchAsksUserToChoose() {
        guard case .ambiguous(_, let candidates) = resolve([alpha, alphaBeta], .some("alph")) else {
            return XCTFail("Expected ambiguous resolution")
        }
        XCTAssertEqual(Set(candidates.map(\.name)), ["Alpha", "AlphaBeta"])
    }

    func testUnknownNameIsNotFoundRatherThanAGuessedPath() {
        XCTAssertEqual(
            resolve([alpha], .some("does-not-exist")),
            .notFound(query: "does-not-exist")
        )
    }

    func testAbsentOrBlankQueryWithSingleProjectResolvesToIt() {
        XCTAssertEqual(resolve([alpha], .none()), .resolved(alpha))
        XCTAssertEqual(resolve([alpha], .some("   ")), .resolved(alpha))
    }

    func testAbsentQueryWithMultipleProjectsNeedsSelection() {
        guard case .needsSelection(let candidates) = resolve([alpha, gamma], .none()) else {
            return XCTFail("Expected needsSelection")
        }
        XCTAssertEqual(candidates.count, 2)
    }

    func testEmptyRegistryNeedsSelectionWithNoCandidates() {
        XCTAssertEqual(resolve([], .none()), .needsSelection(candidates: []))
    }
}

/// The other list questions, also pure.
final class ProjectListFunctionTests: XCTestCase {
    func testProjectIDAtPathIgnoresATrailingSlash() {
        XCTAssertEqual(projectID(atPath: "/tmp/alpha/")([alpha]), .some(alpha.id))
        XCTAssertEqual(projectID(atPath: "/tmp/nowhere")([alpha]), Option.none())
    }

    func testGrantingIsAbsentWhenItWouldChangeNothing() {
        XCTAssertEqual(granting(tool: "git.readOnly", to: alpha.id)([alpha]), Option.none())
        XCTAssertEqual(granting(tool: "anything", to: UUID())([alpha]), Option.none())
    }

    func testGrantingReturnsANewListLeavingTheOriginalAlone() {
        let updated = granting(tool: "git.write", to: alpha.id)([alpha])

        XCTAssertEqual(updated.map { $0[0].allowedTools }^, .some(["git.readOnly", "git.write"]))
        XCTAssertEqual(alpha.allowedTools, ["git.readOnly"], "the input list must not be mutated")
    }

    func testProjectGrantingToolIsAbsentWhenAlreadyAllowed() {
        XCTAssertEqual(alpha.granting(tool: "git.readOnly"), Option.none())
        XCTAssertEqual(alpha.granting(tool: "git.write").map(\.allowedTools)^, .some(["git.readOnly", "git.write"]))
    }
}

final class ProjectRegistryTests: XCTestCase {
    func testAddingTheSamePathTwiceIsDeduplicated() {
        let registry = ProjectRegistry(store: InMemoryProjectStore())
        XCTAssertEqual(registry.add(alpha), .right(true))

        let duplicate = Project(name: "Alpha again", path: alpha.path)
        XCTAssertEqual(
            registry.add(duplicate),
            .right(false),
            "A second add of the same path should be ignored"
        )
        XCTAssertEqual(registry.projects.count, 1)
    }

    func testAddingPathWithTrailingSlashIsTreatedAsDuplicate() {
        let registry = ProjectRegistry(store: InMemoryProjectStore())
        registry.add(Project(name: "A", path: "/tmp/alpha"))
        XCTAssertEqual(registry.add(Project(name: "A2", path: "/tmp/alpha/")), .right(false))
        XCTAssertEqual(registry.projects.count, 1)
    }

    func testAddAndRemovePersistThroughStore() {
        let store = InMemoryProjectStore()
        let registry = ProjectRegistry(store: store)

        registry.add(alpha)
        XCTAssertEqual(store.load(), .right([alpha]))

        registry.remove(id: alpha.id)
        XCTAssertEqual(store.load(), .right([]))
        XCTAssertTrue(registry.projects.isEmpty)
    }

    func testGrantAddsToolOnceAndPersists() {
        let store = InMemoryProjectStore()
        let registry = ProjectRegistry(store: store)
        registry.add(gamma)

        XCTAssertEqual(registry.grant(tool: "git.readOnly", to: gamma.id), .right(true))
        XCTAssertEqual(registry.grant(tool: "git.readOnly", to: gamma.id), .right(false))
        XCTAssertEqual(registry.grant(tool: "git.readOnly", to: UUID()), .right(false))
        XCTAssertEqual(store.load().map { $0[0].allowedTools }^, .right(["git.readOnly"]))
    }

    func testProjectLookupIsAnOption() {
        let registry = ProjectRegistry(store: InMemoryProjectStore(projects: [alpha]))
        XCTAssertEqual(registry.project(id: alpha.id), .some(alpha))
        XCTAssertEqual(registry.project(id: UUID()), Option.none())
    }

    /// A store that cannot be written must not leave the in-memory list ahead
    /// of the file — that is exactly the drift the value-typed design prevents.
    func testAFailedWriteLeavesTheListUnchanged() {
        let registry = ProjectRegistry(store: FailingProjectStore())
        let result = registry.add(alpha)

        XCTAssertEqual(result, .left(.writeFailed(path: "/dev/null", message: "disk is on fire")))
        XCTAssertTrue(registry.projects.isEmpty)
    }

    func testARegistryWhoseStoreFailsToLoadStartsEmpty() {
        XCTAssertTrue(ProjectRegistry(store: FailingProjectStore()).projects.isEmpty)
    }

    func testAllowsToolReflectsAllowlist() {
        XCTAssertTrue(alpha.allows(tool: "git.readOnly"))
        XCTAssertFalse(alpha.allows(tool: "git.write"))
        XCTAssertFalse(gamma.allows(tool: "git.readOnly"))
    }
}

final class ProjectPersistenceTests: XCTestCase {
    func testProjectRoundTripsThroughJSON() {
        let store = FileProjectStore(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("registry-test-\(UUID().uuidString).json")
        )
        XCTAssertTrue(store.save([alpha, gamma]).isRight)
        XCTAssertEqual(store.load(), .right([alpha, gamma]))
    }

    /// The DTO keeps the `description` key, so files written before the domain
    /// type split in two still load.
    func testLegacyJSONWithDescriptionKeyStillLoads() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("legacy-\(UUID().uuidString).json")
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","name":"Legacy","path":"/tmp/legacy",\
        "description":"an old note","allowedTools":[],"allowedActions":[]}]
        """
        try Data(json.utf8).write(to: url)

        let loaded = FileProjectStore(fileURL: url).load()

        XCTAssertEqual(loaded.map { $0.map(\.summary) }^, .right([.some("an old note")]))
        XCTAssertEqual(loaded.map { $0.map(\.id) }^, .right([id]))
    }

    func testAbsentSummaryRoundTripsAsAMissingKey() {
        let project = Project(name: "NoNote", path: "/tmp/nonote")
        XCTAssertNil(project.dto.description)
        XCTAssertEqual(Project(project.dto), project)
    }

    func testUnreadableJSONFailsOnTheLeftRailRatherThanThrowing() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("broken-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: url)

        let decodeFailed = FileProjectStore(fileURL: url).load().fold(
            { error in if case .decodeFailed = error { return true } else { return false } },
            { _ in false }
        )

        XCTAssertTrue(decodeFailed, "Expected a decode failure on the left rail")
    }
}

/// Always fails, to prove failures surface as values.
private final class FailingProjectStore: ProjectStoring, @unchecked Sendable {
    private let error = ProjectStoreError.writeFailed(path: "/dev/null", message: "disk is on fire")

    func load() -> Either<ProjectStoreError, [Project]> { .left(error) }
    func save(_ projects: [Project]) -> Either<ProjectStoreError, Void> { .left(error) }
}
