import XCTest
@testable import ProjectRegistry

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

    func testAdoptionNeverOverwritesARegistrySheAlreadyHasNorSilentlyReGrantsToolsSheRemoved() {
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

    func testEachCharacterGetsHerOwnFile() {
        let one = FileProjectStore.url(forCharacter: UUID())
        let other = FileProjectStore.url(forCharacter: UUID())

        XCTAssertNotEqual(one, other)
        XCTAssertEqual(one.deletingLastPathComponent(), other.deletingLastPathComponent())
    }

    func testTheSharedFileKeepsItsOwnNameSoASecondLaunchCanStillSeeThereWasSomethingToAdopt() {
        let id = UUID()

        XCTAssertNotEqual(FileProjectStore.legacySharedFile, FileProjectStore.url(forCharacter: id))
        XCTAssertEqual(FileProjectStore.legacySharedFile.lastPathComponent, "projects.json")
        XCTAssertEqual(
            FileProjectStore.url(forCharacter: id).lastPathComponent,
            "projects-\(id.uuidString).json"
        )
    }

    func testApprovingAToolForOneCharacterLeavesTheOtherWithoutBecauseAProjectRowCarriesItsApprovals() {
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
