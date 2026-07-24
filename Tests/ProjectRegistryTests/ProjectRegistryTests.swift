import XCTest
@testable import ProjectRegistry

final class ProjectRegistryTests: XCTestCase {
    private func makeRegistry(_ projects: [Project]) -> ProjectRegistry {
        ProjectRegistry(store: InMemoryProjectStore(projects: projects))
    }

    private let alpha = Project(name: "Alpha", path: "/tmp/alpha", allowedTools: ["git.readOnly"])
    private let alphaBeta = Project(name: "AlphaBeta", path: "/tmp/alphabeta")
    private let gamma = Project(name: "Gamma", path: "/tmp/gamma")

    func testExactNameResolvesEvenWhenAnotherNameContainsIt() {
        let registry = makeRegistry([alpha, alphaBeta])
        XCTAssertEqual(registry.resolve(query: "Alpha"), .resolved(alpha))
    }

    func testCaseInsensitiveAndTrimmedMatching() {
        let registry = makeRegistry([alpha])
        XCTAssertEqual(registry.resolve(query: "  aLpHa "), .resolved(alpha))
    }

    func testPartialMatchResolvesWhenUnique() {
        let registry = makeRegistry([alpha, gamma])
        XCTAssertEqual(registry.resolve(query: "gam"), .resolved(gamma))
    }

    func testAmbiguousPartialMatchAsksUserToChoose() {
        let registry = makeRegistry([alpha, alphaBeta])
        guard case .ambiguous(_, let candidates) = registry.resolve(query: "alph") else {
            return XCTFail("Expected ambiguous resolution")
        }
        XCTAssertEqual(Set(candidates.map(\.name)), ["Alpha", "AlphaBeta"])
    }

    func testUnknownNameIsNotFoundRatherThanAGuessedPath() {
        let registry = makeRegistry([alpha])
        XCTAssertEqual(registry.resolve(query: "does-not-exist"), .notFound(query: "does-not-exist"))
    }

    func testEmptyQueryWithSingleProjectResolvesToIt() {
        let registry = makeRegistry([alpha])
        XCTAssertEqual(registry.resolve(query: nil), .resolved(alpha))
        XCTAssertEqual(registry.resolve(query: "   "), .resolved(alpha))
    }

    func testEmptyQueryWithMultipleProjectsNeedsSelection() {
        let registry = makeRegistry([alpha, gamma])
        guard case .needsSelection(let candidates) = registry.resolve(query: nil) else {
            return XCTFail("Expected needsSelection")
        }
        XCTAssertEqual(candidates.count, 2)
    }

    func testEmptyRegistryNeedsSelectionWithNoCandidates() {
        let registry = makeRegistry([])
        XCTAssertEqual(registry.resolve(query: nil), .needsSelection(candidates: []))
    }

    func testAddingTheSamePathTwiceIsDeduplicated() throws {
        let registry = ProjectRegistry(store: InMemoryProjectStore())
        XCTAssertTrue(try registry.add(alpha))

        let duplicate = Project(name: "Alpha again", path: alpha.path)
        XCTAssertFalse(try registry.add(duplicate), "A second add of the same path should be ignored")
        XCTAssertEqual(registry.projects.count, 1)
    }

    func testAddingPathWithTrailingSlashIsTreatedAsDuplicate() throws {
        let registry = ProjectRegistry(store: InMemoryProjectStore())
        try registry.add(Project(name: "A", path: "/tmp/alpha"))
        XCTAssertFalse(try registry.add(Project(name: "A2", path: "/tmp/alpha/")))
        XCTAssertEqual(registry.projects.count, 1)
    }

    func testAddAndRemovePersistThroughStore() throws {
        let store = InMemoryProjectStore()
        let registry = ProjectRegistry(store: store)

        try registry.add(alpha)
        XCTAssertEqual(try store.load(), [alpha])

        try registry.remove(id: alpha.id)
        XCTAssertEqual(try store.load(), [])
        XCTAssertTrue(registry.projects.isEmpty)
    }

    func testAllowsToolReflectsAllowlist() {
        XCTAssertTrue(alpha.allows(tool: "git.readOnly"))
        XCTAssertFalse(alpha.allows(tool: "git.write"))
        XCTAssertFalse(gamma.allows(tool: "git.readOnly"))
    }

    func testProjectRoundTripsThroughJSON() throws {
        let store = FileProjectStore(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("registry-test-\(UUID().uuidString).json")
        )
        try store.save([alpha, gamma])
        XCTAssertEqual(try store.load(), [alpha, gamma])
    }
}
