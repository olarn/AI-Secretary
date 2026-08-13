import XCTest
@testable import ProjectRegistry

/// Handing the shared registry to a character now that each has her own.
///
/// Only ever runs on a machine that has the old file, so it cannot be checked
/// by launching a fresh build — and getting it wrong costs the person every
/// project they had registered, along with the tool approvals attached to them.
final class PerCharacterFileTests: XCTestCase {
    private let legacy = URL(fileURLWithPath: "/tmp/AISecretary/projects.json")
    private let mine = URL(fileURLWithPath: "/tmp/AISecretary/projects-ABC.json")

    func testTheSharedFileBecomesHersWhenSheHasNoneOfHerOwn() {
        XCTAssertEqual(
            perCharacterFileMigration(
                legacy: legacy,
                perCharacter: mine,
                legacyExists: true,
                perCharacterExists: false
            ),
            .adopt(from: legacy, to: mine)
        )
    }

    /// The one that would hurt: adopting on top of a file she already has would
    /// replace the projects she has registered since with what everybody shared
    /// before — and silently re-grant tools she may have removed.
    func testAdoptionNeverOverwritesARegistrySheAlreadyHas() {
        XCTAssertEqual(
            perCharacterFileMigration(
                legacy: legacy,
                perCharacter: mine,
                legacyExists: true,
                perCharacterExists: true
            ),
            .none
        )
    }

    func testAFreshInstallHasNothingToAdopt() {
        XCTAssertEqual(
            perCharacterFileMigration(
                legacy: legacy,
                perCharacter: mine,
                legacyExists: false,
                perCharacterExists: false
            ),
            .none
        )
    }

    func testACharacterWithHerOwnFileAndNoOldFileIsLeftAlone() {
        XCTAssertEqual(
            perCharacterFileMigration(
                legacy: legacy,
                perCharacter: mine,
                legacyExists: false,
                perCharacterExists: true
            ),
            .none
        )
    }

    // MARK: - Where the files go

    func testEachCharacterGetsHerOwnFile() {
        let one = FileProjectStore.url(forCharacter: UUID())
        let other = FileProjectStore.url(forCharacter: UUID())

        XCTAssertNotEqual(one, other)
        XCTAssertEqual(one.deletingLastPathComponent(), other.deletingLastPathComponent())
    }

    /// The shared file keeps its own name rather than being one character's by
    /// coincidence, so a second launch can still see there was something to
    /// adopt.
    func testTheSharedFileIsNobodysOwnFile() {
        let id = UUID()

        XCTAssertNotEqual(FileProjectStore.defaultURL, FileProjectStore.url(forCharacter: id))
        XCTAssertEqual(FileProjectStore.defaultURL.lastPathComponent, "projects.json")
        XCTAssertEqual(
            FileProjectStore.url(forCharacter: id).lastPathComponent,
            "projects-\(id.uuidString).json"
        )
    }

    // MARK: - What separation is for

    /// Registering a project is approving a directory, and a project row
    /// carries the tools approved in it. Two registries must not be able to
    /// reach each other's — this is the rule the whole change exists to make
    /// true, stated where it can fail loudly.
    func testApprovingAToolForOneCharacterLeavesTheOtherWithout() {
        let hers = ProjectRegistry(store: InMemoryProjectStore())
        let his = ProjectRegistry(store: InMemoryProjectStore())
        let project = Project(
            name: "AI Secretary",
            path: "/Users/someone/Desktop/AI-Secretary",
            allowedTools: [],
            allowedActions: []
        )
        _ = hers.add(project)

        _ = hers.grant(tool: "claude-code", to: project.id)

        XCTAssertTrue(hers.project(id: project.id).getOrElse(project).allows(tool: "claude-code"))
        XCTAssertTrue(his.projects.isEmpty)
        XCTAssertFalse(his.containsProject(atPath: project.path))
    }
}
