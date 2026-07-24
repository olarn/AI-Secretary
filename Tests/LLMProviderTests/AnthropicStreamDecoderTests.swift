import XCTest
@testable import LLMProvider

final class AnthropicStreamDecoderTests: XCTestCase {
    func testWalksAThinkingThenTextThenStopSequence() {
        var decoder = AnthropicStreamDecoder()

        XCTAssertNil(decoder.handle(dataLine: #"{"type":"message_start","message":{"usage":{"input_tokens":12}}}"#))
        XCTAssertEqual(
            decoder.handle(dataLine: #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}"#),
            .thinking
        )
        // A thinking delta produces nothing visible.
        XCTAssertNil(decoder.handle(dataLine: #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"…"}}"#))
        XCTAssertNil(decoder.handle(dataLine: #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#))
        XCTAssertEqual(
            decoder.handle(dataLine: #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}"#),
            .textDelta("Hello")
        )
        XCTAssertEqual(
            decoder.handle(dataLine: #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" there"}}"#),
            .textDelta(" there")
        )
        XCTAssertNil(decoder.handle(dataLine: #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}}"#))

        let completion = decoder.handle(dataLine: #"{"type":"message_stop"}"#)
        XCTAssertEqual(completion, .completed(stopReason: "end_turn", usage: ChatUsage(inputTokens: 12, outputTokens: 7)))
    }

    func testRefusalStopReasonIsCarriedToCompletion() {
        var decoder = AnthropicStreamDecoder()
        _ = decoder.handle(dataLine: #"{"type":"message_start","message":{"usage":{"input_tokens":3}}}"#)
        _ = decoder.handle(dataLine: #"{"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{"output_tokens":0}}"#)

        XCTAssertEqual(
            decoder.handle(dataLine: #"{"type":"message_stop"}"#),
            .completed(stopReason: "refusal", usage: ChatUsage(inputTokens: 3, outputTokens: 0))
        )
    }

    func testUnknownAndMalformedLinesAreIgnored() {
        var decoder = AnthropicStreamDecoder()
        XCTAssertNil(decoder.handle(dataLine: #"{"type":"ping"}"#))
        XCTAssertNil(decoder.handle(dataLine: #"{"type":"some_future_event","foo":1}"#))
        XCTAssertNil(decoder.handle(dataLine: "not json at all"))
        XCTAssertNil(decoder.handle(dataLine: ""))
    }
}

final class ChatTypeValidationTests: XCTestCase {
    func testModelResolutionIsCaseInsensitiveAndAllowlisted() {
        XCTAssertEqual(ChatModel.named("claude-sonnet-5"), .sonnet5)
        XCTAssertEqual(ChatModel.named("  CLAUDE-OPUS-4-8 "), .opus48)
        XCTAssertNil(ChatModel.named("gpt-4"))
        XCTAssertNil(ChatModel.named("claude-made-up"))
    }

    func testEffortResolution() {
        XCTAssertEqual(Effort.named("HIGH"), .high)
        XCTAssertEqual(Effort.named("xhigh"), .xhigh)
        XCTAssertNil(Effort.named("turbo"))
    }
}
