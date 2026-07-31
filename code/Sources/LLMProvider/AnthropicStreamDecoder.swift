import FunctionalCore
import Foundation

/// Turns Anthropic SSE `data:` payloads into `ChatStreamEvent`s. Deliberately
/// free of any networking so it can be unit-tested with canned bytes. Unknown
/// or future event types are ignored rather than treated as errors.
public struct AnthropicStreamDecoder {
    private var inputTokens = 0
    private var outputTokens = 0
    private var cacheWriteTokens = 0
    private var cacheReadTokens = 0
    private var stopReason: Option<String> = .none()

    public init() {}

    /// Feed one `data:` JSON payload (already stripped of the `data:` prefix).
    /// Absent for events that only update state, or that we don't consume.
    public mutating func handle(dataLine json: String) -> Option<ChatStreamEvent> {
        guard let data = json.data(using: .utf8) else { return .none() }
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return .none() }

        switch envelope.type {
        case "message_start":
            if let event = try? decoder.decode(MessageStart.self, from: data) {
                inputTokens = event.message.usage?.input_tokens ?? 0
                cacheWriteTokens = event.message.usage?.cache_creation_input_tokens ?? 0
                cacheReadTokens = event.message.usage?.cache_read_input_tokens ?? 0
            }
            return .none()

        case "content_block_start":
            if let event = try? decoder.decode(ContentBlockStart.self, from: data),
               event.content_block.type == "thinking" {
                return .some(.thinking)
            }
            return .none()

        case "content_block_delta":
            if let event = try? decoder.decode(ContentBlockDelta.self, from: data),
               event.delta.type == "text_delta",
               let text = event.delta.text {
                return .some(.textDelta(text))
            }
            return .none()

        case "message_delta":
            if let event = try? decoder.decode(MessageDelta.self, from: data) {
                if let reason = event.delta.stop_reason { stopReason = .some(reason) }
                if let out = event.usage?.output_tokens { outputTokens = out }
            }
            return .none()

        case "message_stop":
            return .some(
                .completed(
                    stopReason: stopReason,
                    usage: .some(ChatUsage(
                        inputTokens: inputTokens,
                        outputTokens: outputTokens,
                        cacheWriteTokens: cacheWriteTokens,
                        cacheReadTokens: cacheReadTokens
                    ))
                )
            )

        default:
            return .none()
        }
    }

    // MARK: - Wire shapes (only the fields we consume)

    private struct Envelope: Decodable { let type: String }

    private struct MessageStart: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
            }
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
