import FunctionalCore
import XCTest
@testable import LLMProvider

/// Recognising that a browser action was blocked.
///
/// Found in use: asking the assistant to scroll an inbox produced "Claude in
/// Chrome requires permission", which matched none of the phrases the app knew,
/// so the refusal was never recognised. It reported the wording as prose and
/// never offered to allow it — the offer is the only way permissions widen
/// here, so the action was simply unreachable. Driving the app confirmed the
/// grant is what unblocks it: with the rule allowed, the same scroll succeeded.
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

    /// "requires permission" is broad. Left unscoped, an unrelated tool failing
    /// for its own reasons would be read as blocked, and the user would be
    /// offered a grant for something that was never refused.
    func testTheSameWordingFromAnotherToolIsNotARefusal() {
        XCTAssertFalse(ClaudeCodeProvider.isPermissionRefusal(refusal, tool: "Bash"))
        XCTAssertFalse(ClaudeCodeProvider.isPermissionRefusal(refusal, tool: "Read"))
        XCTAssertFalse(ClaudeCodeProvider.isPermissionRefusal(refusal))
    }

    /// The refusals the app already understood must keep working, for every
    /// tool including the browser's.
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

    // MARK: - What the approval card says

    /// The rule name is what gets granted, but it is not what the person is
    /// deciding about. One tool covers scrolling, clicking and typing, and the
    /// allowlist can't split them — so the description has to admit the whole
    /// scope rather than name the one action that was asked for.
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

    /// A tool a later extension adds still gets a sentence rather than a raw
    /// `mcp__…` name.
    func testAnUnknownBrowserToolIsStillDescribedInWords() {
        let described = BrowserTools.humanDescription(
            for: "mcp__claude-in-chrome__something_new"
        )^.getOrElse("")
        XCTAssertTrue(described.contains("browser"), "Got: \(described)")
    }
}
