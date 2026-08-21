import XCTest
@testable import LLMProvider

/// The wall nobody was told about.
///
/// Every message here is Claude Code's own wording, captured from a real
/// refusal while driving the app on 2026-08-20 — not invented for the test.
/// The bug was that it matched none of the permission phrases, so no card was
/// ever raised and the work simply stopped.
final class DirectoryRefusalTests: XCTestCase {
    private let real = """
    ls in '/Users/Olarn/Temp/ai-probe-watch' was blocked. For security, Claude Code may only \
    list files in the allowed working directories for this session: '/Users/Olarn/Temp/ai-team-work'.
    """

    func testTheRealRefusalIsRecognised() {
        XCTAssertTrue(isDirectoryRefusal(real))
    }

    /// The permission wall and the directory wall are different walls, and the
    /// second must not be read as the first: a tool rule does not open it.
    func testAnOrdinaryPermissionRefusalIsNotThisOne() {
        XCTAssertFalse(isDirectoryRefusal("Claude requested permissions to use Write, but you haven't granted it yet."))
        XCTAssertFalse(isDirectoryRefusal("This Bash command contains multiple operations. The following parts require approval: mv"))
    }

    /// "was blocked" on its own is far too broad — plenty of ordinary failures
    /// say it — so the phrase that names *this* wall is what decides.
    func testBlockedAloneIsNotEnough() {
        XCTAssertFalse(isDirectoryRefusal("The request was blocked by the server."))
    }

    // MARK: - Which folder to ask for

    /// A write names the file; the folder that has to be opened is the one it
    /// would land in.
    func testAWriteAsksForTheFolderTheFileWouldLandIn() {
        XCTAssertEqual(
            blockedDirectory(
                tool: "Write",
                input: ["file_path": "/Users/Olarn/Temp/ai-team-work/2.actions/task.md"],
                message: real
            ),
            "/Users/Olarn/Temp/ai-team-work/2.actions"
        )
    }

    /// A search names the folder outright, and asking for its parent would open
    /// more than was needed.
    func testASearchAsksForTheFolderItNamed() {
        XCTAssertEqual(
            blockedDirectory(
                tool: "Grep",
                input: ["path": "/Users/Olarn/Temp/ai-team-work/1.inbox"],
                message: real
            ),
            "/Users/Olarn/Temp/ai-team-work/1.inbox"
        )
    }

    /// `Bash` has no path field to read, so the folder comes out of the
    /// sentence — and it has to be the one that was *refused*, which the
    /// refusal names first, not the allowed one it names afterwards.
    func testBashTakesTheRefusedPathAndNotTheAllowedOne() {
        XCTAssertEqual(
            blockedDirectory(tool: "Bash", input: ["command": "ls '/Users/Olarn/Temp/ai-probe-watch'"], message: real),
            "/Users/Olarn/Temp/ai-probe-watch"
        )
    }

    /// Nothing to go on means no card, rather than a card offering a folder
    /// nobody chose.
    func testNothingIsInventedWhenThereIsNoPath() {
        XCTAssertNil(
            blockedDirectory(tool: "Bash", input: ["command": "ls"], message: "blocked, allowed working directories")
        )
    }

    /// A relative path is not a folder we can name to `--add-dir`, and guessing
    /// what it is relative to is exactly the wrong-folder hazard.
    func testARelativePathIsNotUsed() {
        XCTAssertNil(
            blockedDirectory(tool: "Write", input: ["file_path": "2.actions/task.md"], message: "allowed working directories")
        )
    }

    // MARK: - What the rest of the app is handed

    /// The whole point: the event now carries the folder, so `offerToWiden` has
    /// something to put on a card. Before this it carried a tool rule, which
    /// opens a different wall entirely.
    func testTheDeniedToolCarriesTheFolder() {
        let denied = ClaudeCodeProvider.describe(
            tool: "Write",
            input: ["file_path": "/Users/Olarn/Temp/ai-team-work/2.actions/task.md"],
            message: real
        )
        XCTAssertEqual(denied.directory.toOptional(), "/Users/Olarn/Temp/ai-team-work/2.actions")
    }

    /// And an ordinary refusal still carries none, so the person is not asked
    /// to open a folder that was never in the way.
    func testAnOrdinaryRefusalCarriesNoFolder() {
        let denied = ClaudeCodeProvider.describe(
            tool: "Write",
            input: ["file_path": "/tmp/out.txt"],
            message: "Claude requested permissions to use Write, but you haven't granted it yet."
        )
        XCTAssertNil(denied.directory.toOptional())
        XCTAssertEqual(denied.rules, ["Write"])
    }
}
