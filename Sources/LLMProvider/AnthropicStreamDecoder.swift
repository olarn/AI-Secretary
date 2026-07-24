import Foundation

/// Turns Anthropic SSE `data:` payloads into `ChatStreamEvent`s. Deliberately
/// free of any networking so it can be unit-tested with canned bytes. Unknown
/// or future event types are ignored rather than treated as errors.
public struct AnthropicStreamDecoder {
    private var inputTokens = 0
    private var outputTokens = 0
    private var stopReason: String?

    public init() {}

    /// Feed one `data:` JSON payload (already stripped of the `data:` prefix).
    /// Returns an event to emit, or nil for events that only update state.
    public mutating func handle(dataLine json: String) -> ChatStreamEvent? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return nil }

        switch envelope.type {
        case "message_start":
            if let event = try? decoder.decode(MessageStart.self, from: data) {
                inputTokens = event.message.usage?.input_tokens ?? 0
            }
            return nil

        case "content_block_start":
            if let event = try? decoder.decode(ContentBlockStart.self, from: data),
               event.content_block.type == "thinking" {
                return .thinking
            }
            return nil

        case "content_block_delta":
            if let event = try? decoder.decode(ContentBlockDelta.self, from: data),
               event.delta.type == "text_delta",
               let text = event.delta.text {
                return .textDelta(text)
            }
            return nil

        case "message_delta":
            if let event = try? decoder.decode(MessageDelta.self, from: data) {
                if let reason = event.delta.stop_reason { stopReason = reason }
                if let out = event.usage?.output_tokens { outputTokens = out }
            }
            return nil

        case "message_stop":
            return .completed(
                stopReason: stopReason,
                usage: ChatUsage(inputTokens: inputTokens, outputTokens: outputTokens)
            )

        default:
            return nil
        }
    }

    // MARK: - Wire shapes (only the fields we consume)

    private struct Envelope: Decodable { let type: String }

    private struct MessageStart: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable { let input_tokens: Int? }
            let usage: Usage?
        }
        let message: Message
    }

    private struct ContentBlockStart: Decodable {
        struct Block: Decodable { let type: String }
        let content_block: Block
    }

    private struct ContentBlockDelta: Decodable {
        struct Delta: Decodable {
            let type: String
            let text: String?
        }
        let delta: Delta
    }

    private struct MessageDelta: Decodable {
        struct Delta: Decodable { let stop_reason: String? }
        struct Usage: Decodable { let output_tokens: Int? }
        let delta: Delta
        let usage: Usage?
    }
}
