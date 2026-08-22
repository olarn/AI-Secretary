import Foundation
import FunctionalCore
import XCTest
@testable import LLMProvider

final class UsageParsingTests: XCTestCase {
    private func makeProvider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            installation: ClaudeCodeInstallation(executableURL: URL(fileURLWithPath: "/bin/echo"))
        )
    }

    private func usage(from line: String) throws -> ChatUsage {
        let events = makeProvider().handle(line: line)
        guard case .completed(_, let usage)? = events.first else {
            throw XCTSkip("Expected a completed event, got \(events)")
        }
        return try XCTUnwrap(usage.toOptional())
    }

    private static let measured = #"""
    {"type":"result","subtype":"success","stop_reason":"end_turn","total_cost_usd":0.0780198,"usage":{"input_tokens":2,"output_tokens":5,"cache_creation_input_tokens":11768,"cache_read_input_tokens":24436},"modelUsage":{"claude-sonnet-5":{"inputTokens":2,"outputTokens":5,"costUSD":0.0780198,"contextWindow":1000000,"maxOutputTokens":64000}}}
    """#

    func testEveryTokenCountIsRead() throws {
        let counts = try usage(from: Self.measured)
        XCTAssertEqual(counts.inputTokens, 2)
        XCTAssertEqual(counts.outputTokens, 5)
        XCTAssertEqual(counts.cacheWriteTokens, 11_768)
        XCTAssertEqual(counts.cacheReadTokens, 24_436)
    }

    func testCostAndContextWindowAreRead() throws {
        let counts = try usage(from: Self.measured)
        XCTAssertEqual(counts.costUSD, 0.0780198, accuracy: 0.000001)
        XCTAssertEqual(counts.contextWindow, 1_000_000)
    }

    func testALineWithoutTheExtrasStillCompletes() throws {
        let counts = try usage(
            from: #"{"type":"result","subtype":"success","usage":{"input_tokens":7,"output_tokens":9}}"#
        )
        XCTAssertEqual(counts.inputTokens, 7)
        XCTAssertEqual(counts.outputTokens, 9)
        XCTAssertEqual(counts.cacheWriteTokens, 0)
        XCTAssertEqual(counts.costUSD, 0)
        XCTAssertNil(counts.contextWindow)
    }

    func testTheContextWindowIsFoundWhateverTheModelIsCalled() {
        XCTAssertEqual(
            ClaudeCodeProvider.contextWindow(of: [
                "modelUsage": ["some-future-model": ["contextWindow": 512_000]]
            ]),
            512_000
        )
        XCTAssertNil(ClaudeCodeProvider.contextWindow(of: ["modelUsage": [:]]))
        XCTAssertNil(ClaudeCodeProvider.contextWindow(of: [:]))
    }
}
