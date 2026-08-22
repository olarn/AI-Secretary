import FunctionalCore
import XCTest
@testable import LLMProvider

final class BrowserRefusalTests: XCTestCase {
    private let refusal = "Claude in Chrome requires permission"

    func testTheBrowsersOwnWordingCountsAsARefusal() {
        XCTAssertTrue(
            ClaudeCodeProvider.isPermissionRefusal(
                refusal,
                tool: BrowserTools.rule(for: "computer")
            )
        )
    }

    func testTheSameWordingFromAnotherToolIsNotARefusal() {
        XCTAssertFalse(ClaudeCodeProvider.isPermissionRefusal(refusal, tool: "Bash"))
        XCTAssertFalse(ClaudeCodeProvider.isPermissionRefusal(refusal, tool: "Read"))
        XCTAssertFalse(ClaudeCodeProvider.isPermissionRefusal(refusal))
    }

    func testTheExistingWordingsStillCount() {
        for message in [
            "Claude requested permissions to use Write, but you haven't granted it yet",
            "This tool requires approval"
        ] {
            XCTAssertTrue(ClaudeCodeProvider.isPermissionRefusal(message, tool: "Write"))
            XCTAssertTrue(
                ClaudeCodeProvider.isPermissionRefusal(
                    message,
                    tool: BrowserTools.rule(for: "navigate")
                )
            )
        }
    }

    func testAnOrdinaryToolErrorIsNotARefusal() {
        XCTAssertFalse(
            ClaudeCodeProvider.isPermissionRefusal(
                "No tab available",
                tool: BrowserTools.rule(for: "computer")
            )
        )
    }

    func testTheScrollToolIsDescribedByEverythingItCovers() {
        let described = BrowserTools.humanDescription(
            for: BrowserTools.rule(for: "computer")
        )^.getOrElse("")
        XCTAssertTrue(described.contains("scroll"), "Got: \(described)")
        XCTAssertTrue(described.contains("click"), "Got: \(described)")
        XCTAssertTrue(described.contains("type"), "Got: \(described)")
    }

    func testNonBrowserToolsHaveNoBrowserDescription() {
        XCTAssertEqual(BrowserTools.humanDescription(for: "Bash"), Option.none())
    }

    func testAnUnknownBrowserToolIsStillDescribedInWords() {
        let described = BrowserTools.humanDescription(
            for: "mcp__claude-in-chrome__something_new"
        )^.getOrElse("")
        XCTAssertTrue(described.contains("browser"), "Got: \(described)")
    }
}
