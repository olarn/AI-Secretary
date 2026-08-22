import FunctionalCore
import Foundation

public struct AnthropicStreamDecoder {
    private var inputTokens = 0
    private var outputTokens = 0
    private var cacheWriteTokens = 0
    private var cacheReadTokens = 0
    private var stopReason: Option<String> = .none()

    public init() {}

    public mutating func handle(dataLine jsonWithoutTheDataPrefix: String) -> Option<ChatStreamEvent> {
        guard let data = jsonWithoutTheDataPrefix.data(using: .utf8) else { return .none() }
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
