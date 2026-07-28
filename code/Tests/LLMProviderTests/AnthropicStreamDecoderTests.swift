import FunctionalCore
import XCTest
@testable import LLMProvider

final class AnthropicStreamDecoderTests: XCTestCase {
    func testWalksAThinkingThenTextThenStopSequence() {
        var decoder = AnthropicStreamDecoder()

        XCTAssertEqual(decoder.handle(dataLine: #"{"type":"message_start","message":{"usage":{"input_tokens":12}}}"#), Option.none())
        XCTAssertEqual(
            decoder.handle(dataLine: #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}"#),
            .some(.thinking)
        )
        // A thinking delta produces nothing visible.
        XCTAssertEqual(decoder.handle(dataLine: #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"…"}}"#), Option.none())
        XCTAssertEqual(decoder.handle(dataLine: #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#), Option.none())
        XCTAssertEqual(
            decoder.handle(dataLine: #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}"#),
            .some(.textDelta("Hello"))
        )
        XCTAssertEqual(
            decoder.handle(dataLine: #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" there"}}"#),
            .some(.textDelta(" there"))
        )
        XCTAssertEqual(decoder.handle(dataLine: #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}}"#), Option.none())

        let completion = decoder.handle(dataLine: #"{"type":"message_stop"}"#)
        XCTAssertEqual(
            completion,
            .some(.completed(stopReason: .some("end_turn"), usage: .some(ChatUsage(inputTokens: 12, outputTokens: 7))))
        )
    }

    func testRefusalStopReasonIsCarriedToCompletion() {
        var decoder = AnthropicStreamDecoder()
        _ = decoder.handle(dataLine: #"{"type":"message_start","message":{"usage":{"input_tokens":3}}}"#)
        _ = decoder.handle(dataLine: #"{"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{"output_tokens":0}}"#)

        XCTAssertEqual(
            decoder.handle(dataLine: #"{"type":"message_stop"}"#),
            .some(.completed(stopReason: .some("refusal"), usage: .some(ChatUsage(inputTokens: 3, outputTokens: 0))))
        )
    }

    func testUnknownAndMalformedLinesAreIgnored() {
        var decoder = AnthropicStreamDecoder()
        XCTAssertEqual(decoder.handle(dataLine: #"{"type":"ping"}"#), Option.none())
        XCTAssertEqual(decoder.handle(dataLine: #"{"type":"some_future_event","foo":1}"#), Option.none())
        XCTAssertEqual(decoder.handle(dataLine: "not json at all"), Option.none())
        XCTAssertEqual(decoder.handle(dataLine: ""), Option.none())
    }
}

final class ChatTypeValidationTests: XCTestCase {
    func testModelResolutionIsCaseInsensitiveAndAllowlisted() {
        XCTAssertEqual(ChatModel.named("claude-sonnet-5"), .some(.sonnet5))
        XCTAssertEqual(ChatModel.named("  CLAUDE-OPUS-4-8 "), .some(.opus48))
        XCTAssertEqual(ChatModel.named("gpt-4"), Option.none())
        XCTAssertEqual(ChatModel.named("claude-made-up"), Option.none())
    }

    func testEffortResolution() {
        XCTAssertEqual(Effort.named("HIGH"), .some(.high))
        XCTAssertEqual(Effort.named("xhigh"), .some(.xhigh))
        XCTAssertEqual(Effort.named("turbo"), Option.none())
    }
}
