import XCTest
import ProjectRegistry
@testable import ToolAdapters

/// Exercises the adapter against a throwaway repository created per test.
/// Nothing here touches the user's own checkouts.
final class GitReadOnlyAdapterTests: XCTestCase {
    private var fixtureRoot: URL!
    private let adapter = GitReadOnlyAdapter()

    override func setUpWithError() throws {
        fixtureRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("git-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
    }

    private func git(_ args: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
    }

    private func makeRepository() throws -> Project {
        try git(["init", "--initial-branch=main"], in: fixtureRoot)
        try git(["config", "user.email", "test@example.com"], in: fixtureRoot)
        try git(["config", "user.name", "Test"], in: fixtureRoot)
        try "hello\n".write(
            to: fixtureRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try git(["add", "."], in: fixtureRoot)
        try git(["commit", "-m", "initial commit"], in: fixtureRoot)

        return Project(
            name: "Fixture",
            path: fixtureRoot.path,
            allowedTools: [GitReadOnlyAdapter.toolIdentifier]
        )
    }

    func testStatusRunsAndReportsCleanTree() throws {
        let project = try makeRepository()
        let result = try adapter.run(.status, in: project)

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.output.contains("main"), "Expected branch header, got: \(result.output)")
    }

    func testStatusReportsAnUntrackedFile() throws {
        let project = try makeRepository()
        try "tmp\n".write(
            to: fixtureRoot.appendingPathComponent("new.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = try adapter.run(.status, in: project)
        XCTAssertTrue(result.output.contains("new.txt"), "Expected untracked file, got: \(result.output)")
    }

    func testCurrentBranchReturnsTheBranchName() throws {
        let project = try makeRepository()
        let result = try adapter.run(.currentBranch, in: project)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "main")
    }

    func testRecentLogListsTheCommit() throws {
        let project = try makeRepository()
        let result = try adapter.run(.recentLog, in: project)
        XCTAssertTrue(result.output.contains("initial commit"))
    }

    func testDiffStatReportsModifiedFile() throws {
        let project = try makeRepository()
        try "hello again\n".write(
            to: fixtureRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let result = try adapter.run(.diffStat, in: project)
        XCTAssertTrue(result.output.contains("README.md"), "Expected diff stat, got: \(result.output)")
    }

    func testMissingDirectoryIsRejectedBeforeLaunching() {
        let project = Project(
            name: "Ghost",
            path: fixtureRoot.appendingPathComponent("nope").path,
            allowedTools: [GitReadOnlyAdapter.toolIdentifier]
        )

        XCTAssertThrowsError(try adapter.run(.status, in: project)) { error in
            guard case ToolError.projectPathMissing = error else {
                return XCTFail("Expected projectPathMissing, got \(error)")
            }
        }
    }

    func testNonRepositoryDirectoryIsRejected() {
        let project = Project(
            name: "Plain",
            path: fixtureRoot.path,
            allowedTools: [GitReadOnlyAdapter.toolIdentifier]
        )

        XCTAssertThrowsError(try adapter.run(.status, in: project)) { error in
            guard case ToolError.notAGitRepository = error else {
                return XCTFail("Expected notAGitRepository, got \(error)")
            }
        }
    }

    func testMissingExecutableIsReportedRatherThanFallingBackToPath() throws {
        let project = try makeRepository()
        let bogus = GitReadOnlyAdapter(gitExecutable: URL(fileURLWithPath: "/nonexistent/git"))

        XCTAssertThrowsError(try bogus.run(.status, in: project)) { error in
            guard case ToolError.executableMissing = error else {
                return XCTFail("Expected executableMissing, got \(error)")
            }
        }
    }

    /// The allowlist is the argument table itself: every operation must map to
    /// a read-only git subcommand, with no shell metacharacters anywhere.
    func testEveryOperationMapsToAReadOnlyCommand() {
        let readOnlySubcommands: Set<String> = ["status", "diff", "branch", "log"]
        let forbidden = CharacterSet(charactersIn: ";|&$`><\n")

        for operation in [CodeToolOperation.status, .diffStat, .currentBranch, .recentLog] {
            let summary = adapter.summary(for: operation)
            let parts = summary.split(separator: " ").map(String.init)

            XCTAssertEqual(parts.first, "git")
            XCTAssertTrue(
                readOnlySubcommands.contains(parts[1]),
                "\(operation) uses non-read-only subcommand \(parts[1])"
            )
            XCTAssertNil(
                summary.rangeOfCharacter(from: forbidden),
                "\(operation) summary contains shell metacharacters"
            )
            XCTAssertEqual(operation.actionClass, .readOnly)
        }
    }
}
