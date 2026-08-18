import Foundation
import FunctionalCore
import XCTest
@testable import LLMProvider

/// Reading a sub-agent out of Claude Code's stream.
///
/// Every line below is copied from a real capture (2026-08-18, CLI 2.1.234,
/// run with the app's own flags), not invented — the shape of these events is
/// the one fact the whole feature rests on, and a fixture written from memory
/// would pin the wrong thing.
final class SubagentStreamTests: XCTestCase {
    private func makeProvider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            installation: ClaudeCodeInstallation(executableURL: URL(fileURLWithPath: "/bin/echo"))
        )
    }

    // MARK: - The lifecycle Claude Code reports itself

    private static let started = #"""
    {"type":"system","subtype":"task_started","task_id":"a5ad90d14f109d4ca","tool_use_id":"toolu_01LMidRw6cY4tbyvXKVf3MnY","description":"Count files in cwd","subagent_type":"general-purpose","task_type":"local_agent","prompt":"Count how many files are in the current working directory."}
    """#

    private static let progress = #"""
    {"type":"system","subtype":"task_progress","task_id":"a5ad90d14f109d4ca","tool_use_id":"toolu_01LMidRw6cY4tbyvXKVf3MnY","description":"Running Count top-level files","subagent_type":"general-purpose","usage":{"total_tokens":14169,"tool_uses":1,"duration_ms":2672},"last_tool_name":"Bash"}
    """#

    private static let finished = #"""
    {"type":"system","subtype":"task_notification","task_id":"a5ad90d14f109d4ca","tool_use_id":"toolu_01LMidRw6cY4tbyvXKVf3MnY","status":"completed","summary":"3","usage":{"total_tokens":15919,"tool_uses":1,"duration_ms":5239}}
    """#

    func testAStartedSubagentIsNamedAndDescribed() throws {
        let events = makeProvider().handle(line: Self.started)
        guard case .subagentStarted(let task)? = events.first else {
            return XCTFail("Expected a started event, got \(events)")
        }
        XCTAssertEqual(task.id, "a5ad90d14f109d4ca")
        XCTAssertEqual(task.kind, "general-purpose")
        XCTAssertEqual(task.detail, "Count files in cwd")
    }

    /// The heartbeat. It carries what the sub-agent is doing *now*, which is the
    /// half that was missing — and the tool it last reached for, so a long step
    /// can say what it is waiting on.
    func testProgressCarriesTheLiveDescriptionAndLastTool() throws {
        let events = makeProvider().handle(line: Self.progress)
        guard case .subagentProgress(let task)? = events.first else {
            return XCTFail("Expected a progress event, got \(events)")
        }
        XCTAssertEqual(task.detail, "Running Count top-level files")
        XCTAssertEqual(task.lastTool.toOptional(), "Bash")
    }

    func testFinishingCarriesTheSubagentsOwnAnswer() throws {
        let events = makeProvider().handle(line: Self.finished)
        guard case .subagentFinished(let outcome)? = events.first else {
            return XCTFail("Expected a finished event, got \(events)")
        }
        XCTAssertEqual(outcome.status, "completed")
        XCTAssertEqual(outcome.summary, "3")
    }

    /// "It finished" is the half that matters most. A notification with no
    /// summary must still be reported rather than dropped, or the character goes
    /// silent again at exactly the moment she is supposed to speak.
    func testAFinishWithoutASummaryIsStillReported() {
        let line = #"{"type":"system","subtype":"task_notification","task_id":"t1","status":"completed"}"#
        guard case .subagentFinished(let outcome)? = makeProvider().handle(line: line).first else {
            return XCTFail("A summary-less finish must still be an event")
        }
        XCTAssertEqual(outcome.summary, "")
    }

    /// New `system` subtypes arrive between Claude Code releases; an unknown one
    /// is skipped, never treated as a failure. `init` still has to work.
    func testUnknownSystemSubtypesAreIgnoredAndInitStillWorks() {
        XCTAssertTrue(makeProvider().handle(line: #"{"type":"system","subtype":"invented_later"}"#).isEmpty)
        XCTAssertTrue(makeProvider().handle(line: #"{"type":"system","subtype":"task_started"}"#).isEmpty)

        let provider = makeProvider()
        _ = provider.handle(line: #"{"type":"system","subtype":"init","session_id":"still-adopted"}"#)
        XCTAssertEqual(provider.sessionID, "still-adopted")
    }

    // MARK: - Whose work is it

    /// The bug this sprint exists to fix, as a test. A sub-agent's inner tool
    /// call arrives as an ordinary `assistant` line and was shown as the
    /// character's own activity, with nothing to tell the two apart.
    func testASubagentsToolCallIsTaggedAsItsOwn() throws {
        let line = #"""
        {"type":"assistant","parent_tool_use_id":"toolu_01LMidRw6cY4tbyvXKVf3MnY","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_inner","name":"Bash","input":{"command":"ls -a"}}]}}
        """#
        guard case .activity(let activity)? = makeProvider().handle(line: line).first else {
            return XCTFail("Expected an activity event")
        }
        XCTAssertEqual(activity.origin, .subagent("toolu_01LMidRw6cY4tbyvXKVf3MnY"))
    }

    func testTheCharactersOwnToolCallStaysHers() throws {
        let line = #"""
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_outer","name":"Read","input":{"file_path":"/tmp/a.txt"}}]}}
        """#
        guard case .activity(let activity)? = makeProvider().handle(line: line).first else {
            return XCTFail("Expected an activity event")
        }
        XCTAssertEqual(activity.origin, .main)
    }

    /// The one failure a reader could not detect: another agent's prose joined
    /// into the character's reply, with no seam to show where it came from.
    func testASubagentsTextNeverJoinsTheCharactersReply() {
        let line = #"""
        {"type":"stream_event","parent_tool_use_id":"toolu_01LMidRw6cY4tbyvXKVf3MnY","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"counting files"}}}
        """#
        XCTAssertTrue(
            makeProvider().handle(line: line).isEmpty,
            "A sub-agent's words must not be appended to hers"
        )
    }

    func testHerOwnTextStillArrives() {
        let line = #"""
        {"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"here you go"}}}
        """#
        XCTAssertEqual(makeProvider().handle(line: line), [.textDelta("here you go")])
    }
}
