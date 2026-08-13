import FunctionalCore
import Foundation
import XCTest
@testable import LLMProvider

/// When a turn may reuse the process the last turn left running.
///
/// The whole point of keeping one alive is speed — first text 5.47s → 1.15s,
/// measured 2026-08-13 — and the whole risk is answering a turn on a process
/// launched for different terms. Every value below is a command-line flag: it
/// cannot be changed on a running process, so a difference means a new one.
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

    /// Each of these is a launch flag. Changing one on a running process is not
    /// possible, so each has to force a new one — and this is the test that
    /// fails if someone adds a field to the key and forgets what it means.
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

    /// The one that would otherwise restart every second turn: a fresh process
    /// mints its own session and only says so in the init event. Once it is
    /// recorded, the next turn — which now knows the id — must recognise the
    /// process it is already talking to.
    func testAProcessThatMintedItsOwnSessionIsRecognisedNextTurn() {
        let fresh = key(session: nil)
        let known = key(session: "minted-1")

        XCTAssertFalse(known.canBeServed(by: fresh))
        XCTAssertTrue(known.canBeServed(by: key(session: "minted-1")))
    }

    // MARK: - The message on the way in

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

    // MARK: - Where one turn ends

    /// Read past the result line and the next turn's events land on the last
    /// turn's bubble — the failure that only a shared process can have.
    func testTheResultLineIsWhatEndsATurn() {
        XCTAssertTrue(ClaudeCodeProvider.isTurnResult(#"{"type":"result","subtype":"success"}"#))
        XCTAssertFalse(ClaudeCodeProvider.isTurnResult(#"{"type":"stream_event"}"#))
        XCTAssertFalse(ClaudeCodeProvider.isTurnResult(#"{"type":"assistant"}"#))
        XCTAssertFalse(ClaudeCodeProvider.isTurnResult("not json at all"))
        XCTAssertFalse(ClaudeCodeProvider.isTurnResult(""))
    }
}
