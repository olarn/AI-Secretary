import FunctionalCore
import Foundation
import XCTest
@testable import LLMProvider

final class WarmProcessKeyTests: XCTestCase {
    private let project = URL(fileURLWithPath: "/tmp/project")

    private func key(
        workingDirectory: URL? = URL(fileURLWithPath: "/tmp/project"),
        additionalDirectories: [URL] = [],
        allowedTools: [String] = ["Read"],
        permissionMode: String = "manual",
        browserEnabled: Bool = false,
        model: String? = "claude-opus-5",
        effort: String? = nil,
        system: String? = "be brief",
        session: String? = "abc-123"
    ) -> WarmProcessKey {
        WarmProcessKey(
            workingDirectory: workingDirectory,
            additionalDirectories: additionalDirectories,
            allowedTools: allowedTools,
            permissionMode: permissionMode,
            browserEnabled: browserEnabled,
            model: model,
            effort: effort,
            system: system,
            session: session
        )
    }

    func testTheSameConversationOnTheSameTermsReusesTheProcess() {
        XCTAssertTrue(key().canBeServed(by: key()))
    }

    func testEveryLaunchFlagForcesANewProcess() {
        let running = key()
        let changed: [(String, WarmProcessKey)] = [
            ("working directory", key(workingDirectory: URL(fileURLWithPath: "/tmp/other"))),
            ("no working directory", key(workingDirectory: nil)),
            ("added directory", key(additionalDirectories: [project])),
            ("allowed tools", key(allowedTools: ["Read", "Write"])),
            ("permission mode", key(permissionMode: "acceptEdits")),
            ("browser", key(browserEnabled: true)),
            ("model", key(model: "claude-sonnet-5")),
            ("effort", key(effort: "xhigh")),
            ("system prompt", key(system: "be thorough")),
            ("session", key(session: "def-456")),
        ]

        for (what, wanted) in changed {
            XCTAssertFalse(wanted.canBeServed(by: running), "Should have restarted for: \(what)")
        }
    }

    func testAProcessThatMintedItsOwnSessionIsRecognisedNextTurn() {
        let fresh = key(session: nil)
        let known = key(session: "minted-1")

        XCTAssertFalse(known.canBeServed(by: fresh))
        XCTAssertTrue(known.canBeServed(by: key(session: "minted-1")))
    }

    func testTheMessageGoesAsOneJSONLineTheCLICanRead() throws {
        let line = try XCTUnwrap(warmTurnInputLine(prompt: "hello"))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["type"] as? String, "user")
        let message = try XCTUnwrap(object["message"] as? [String: Any])
        XCTAssertEqual(message["role"] as? String, "user")
        let content = try XCTUnwrap(message["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "hello")
    }

    func testTheResultLineIsWhatEndsATurn() {
        XCTAssertTrue(ClaudeCodeProvider.isTurnResult(#"{"type":"result","subtype":"success"}"#))
        XCTAssertFalse(ClaudeCodeProvider.isTurnResult(#"{"type":"stream_event"}"#))
        XCTAssertFalse(ClaudeCodeProvider.isTurnResult(#"{"type":"assistant"}"#))
        XCTAssertFalse(ClaudeCodeProvider.isTurnResult("not json at all"))
        XCTAssertFalse(ClaudeCodeProvider.isTurnResult(""))
    }
}
