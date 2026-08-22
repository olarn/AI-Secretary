import XCTest
@testable import LLMProvider

final class DirectoryRefusalTests: XCTestCase {
    private let real = """
    ls in '/Users/Olarn/Temp/ai-probe-watch' was blocked. For security, Claude Code may only \
    list files in the allowed working directories for this session: '/Users/Olarn/Temp/ai-team-work'.
    """

    func testTheRealRefusalIsRecognised() {
        XCTAssertTrue(isDirectoryRefusal(real))
    }

    func testAnOrdinaryPermissionRefusalIsNotThisOne() {
        XCTAssertFalse(isDirectoryRefusal("Claude requested permissions to use Write, but you haven't granted it yet."))
        XCTAssertFalse(isDirectoryRefusal("This Bash command contains multiple operations. The following parts require approval: mv"))
    }

    func testBlockedAloneIsNotEnough() {
        XCTAssertFalse(isDirectoryRefusal("The request was blocked by the server."))
    }

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

    func testBashTakesTheRefusedPathAndNotTheAllowedOne() {
        XCTAssertEqual(
            blockedDirectory(tool: "Bash", input: ["command": "ls '/Users/Olarn/Temp/ai-probe-watch'"], message: real),
            "/Users/Olarn/Temp/ai-probe-watch"
        )
    }

    func testNothingIsInventedWhenThereIsNoPath() {
        XCTAssertNil(
            blockedDirectory(tool: "Bash", input: ["command": "ls"], message: "blocked, allowed working directories")
        )
    }

    func testARelativePathIsNotUsed() {
        XCTAssertNil(
            blockedDirectory(tool: "Write", input: ["file_path": "2.actions/task.md"], message: "allowed working directories")
        )
    }

    func testTheDeniedToolCarriesTheFolder() {
        let denied = ClaudeCodeProvider.describe(
            tool: "Write",
            input: ["file_path": "/Users/Olarn/Temp/ai-team-work/2.actions/task.md"],
            message: real
        )
        XCTAssertEqual(denied.directory.toOptional(), "/Users/Olarn/Temp/ai-team-work/2.actions")
    }

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
