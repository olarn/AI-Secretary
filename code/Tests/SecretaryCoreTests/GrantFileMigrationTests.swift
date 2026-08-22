import FunctionalCore
import Foundation
import Permissions
import ProjectRegistry
import XCTest
@testable import SecretaryCore

final class GrantFileMigrationTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/tmp")
    private let character = UUID(uuidString: "5B1E2A00-0000-4000-8000-000000000001") ?? UUID()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grants-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var permissions: URL {
        directory.appendingPathComponent("permissions-\(character.uuidString).json")
    }

    private var projects: URL {
        directory.appendingPathComponent("projects-\(character.uuidString).json")
    }

    private func writeIdKeyedFile(_ rows: [(String, String)]) throws {
        let body = rows.map { id, tool in
            """
            {"actionClass":"localWrite","projectID":"\(id)","toolID":"\(tool)"}
            """
        }.joined(separator: ",")
        try Data("[\(body)]".utf8).write(to: permissions)
    }

    private func writeProjects(_ rows: [(String, String)]) throws {
        let body = rows.map { id, path in
            """
            {"allowedActions":["read"],"allowedTools":["claude.code"],"id":"\(id)","name":"P","path":"\(path)"}
            """
        }.joined(separator: ",")
        try Data("[\(body)]".utf8).write(to: projects)
    }

    func testTheOldFileBecomesOneRowPerSurvivingProject() throws {
        let live = "901DA562-9187-459F-933E-052C28893037"
        try writeIdKeyedFile([
            (live, "claude.code"),
            (live, "file.readOnly"),
            ("2BFD7BAB-57F5-445F-8FA7-79E5A785DAA6", "claude.code"),
            ("A35B2058-DDAD-4F48-8C82-20259A643883", "claude.code")
        ])
        try writeProjects([(live, "/Users/someone/Second-Brain")])

        let loaded = FileStandingGrantStore(fileURL: permissions).load().getOrElse([])

        XCTAssertEqual(
            loaded,
            [StandingGrant(projectPath: CanonicalPath("/Users/someone/Second-Brain"))],
            "two rows for one project collapse into one, and projects that are gone are dropped"
        )

        let onDisk = try String(contentsOf: permissions, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("projectPath"), "the migration is written back once, not redone every launch")
        XCTAssertFalse(onDisk.contains("2BFD7BAB"), "the dead rows are gone from the file: \(onDisk)")
    }

    func testAProjectListThatIsEmptyLeavesNothingBehind() throws {
        try writeIdKeyedFile([("6999113A-0232-4442-B3C4-0448314F0DC7", "claude.code")])
        try writeProjects([])

        XCTAssertEqual(FileStandingGrantStore(fileURL: permissions).load().getOrElse([]), [])
    }

    func testAnAlreadyMigratedFileIsLeftAlone() throws {
        let store = FileStandingGrantStore(fileURL: permissions)
        let written = [StandingGrant(projectPath: CanonicalPath("/Users/someone/Second-Brain"))]
        XCTAssertTrue(store.save(written).isRight)

        XCTAssertEqual(store.load().getOrElse([]), written)
    }

    func testGibberishLosesNothingBecauseItCannotBeRead() throws {
        try Data("not json at all".utf8).write(to: permissions)

        XCTAssertTrue(FileStandingGrantStore(fileURL: permissions).load().isLeft)
    }

    func testTheMigrationNeedsNoProjectFileToFailSafely() throws {
        try writeIdKeyedFile([("901DA562-9187-459F-933E-052C28893037", "claude.code")])

        XCTAssertEqual(
            FileStandingGrantStore(fileURL: permissions).load().getOrElse([]),
            [],
            "with no project list there is no path to key on, and inventing one would grant the wrong folder"
        )
    }
}
