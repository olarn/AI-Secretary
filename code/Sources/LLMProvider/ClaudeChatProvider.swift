import FunctionalCore
import Foundation
import os

/// Talks to the Anthropic Messages API over raw HTTPS with SSE streaming.
///
/// Safety/correctness properties:
/// - Auth is `x-api-key` (never `Authorization: Bearer`), read fresh from the
///   injected provider so a rotated key is picked up without restart.
/// - No `temperature`/`top_p`/`top_k` — Sonnet 5 rejects them with a 400.
/// - `max_tokens` is always sent; adaptive thinking is left on so the caller can
///   map the pre-first-token pause to a THINKING state.
/// - Nothing sensitive is logged: not the key, not the prompt, not the reply.
public final class ClaudeChatProvider: ChatProvider {
    private let apiKeyProvider: @Sendable () -> String?
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let logger = Logger(subsystem: "com.aisecretary.app", category: "ClaudeChatProvider")

    public init(apiKeyProvider: @escaping @Sendable () -> String?, session: URLSession = .shared) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    public func stream(
        messages: [ChatMessage],
        model: Option<ChatModel>,
        effort: Option<Effort>,
        maxTokens: Int,
        system: Option<String>
    ) -> ChatStream {
        AsyncStream { continuation in
            // The API has no "use your default" — a concrete model and effort
            // must go on the wire, so absence resolves to ours here.
            let model = model.getOrElse(.sonnet5)
            let effort = effort.getOrElse(.medium)
            let system = system.toOptional()
            let task = Task { [apiKeyProvider, session, endpoint, logger] in
                do {
                    guard let key = apiKeyProvider(), !key.isEmpty else {
                        throw ChatError.missingAPIKey
                    }

                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue(key, forHTTPHeaderField: "x-api-key")
                    request.httpBody = try JSONEncoder().encode(
                        RequestBody(
                            model: model.id,
                            maxTokens: maxTokens,
                            effort: effort.rawValue,
                            system: system,
                            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) }
                        )
                    )

                    logger.info("Streaming chat: model=\(model.id, privacy: .public) effort=\(effort.rawValue, privacy: .public)")

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ChatError.network("No HTTP response")
                    }

                    if http.statusCode != 200 {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw ChatError.http(
                            status: http.statusCode,
                            message: Self.errorMessage(status: http.statusCode, body: body)
                        )
                    }

                    var decoder = AnthropicStreamDecoder()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst("data:".count))
                            .trimmingCharacters(in: .whitespaces)
                        decoder.handle(dataLine: payload).fold(
                            {},
                            { continuation.yield(.right($0)) }
                        )
                    }
                } catch is CancellationError {
                    // Nothing to report: the caller asked us to stop.
                } catch {
                    continuation.yield(.left(asChatError(error, otherwise: ChatError.network)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Best-effort human-readable message for a non-200. Falls back to a generic
    /// hint per status so we never surface a raw blob or leak header content.
    private static func errorMessage(status: Int, body: Data) -> String {
        if let decoded = try? JSONDecoder().decode(APIError.self, from: body) {
            return decoded.error.message
        }
        switch status {
        case 401: return "Invalid or missing API key."
        case 429: return "Rate limited — try again shortly."
        case 400: return "The request was rejected."
        default: return "Unexpected server response."
        }
    }

    private struct APIError: Decodable {
        struct Inner: Decodable { let message: String }
        let error: Inner
    }

    private struct RequestBody: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        struct Thinking: Encodable { let type = "adaptive" }
        struct OutputConfig: Encodable { let effort: String }

        let model: String
        let maxTokens: Int
        let stream = true
        let thinking = Thinking()
        let outputConfig: OutputConfig
        let system: String?
        let messages: [Message]

        init(model: String, maxTokens: Int, effort: String, system: String?, messages: [Message]) {
            self.model = model
            self.maxTokens = maxTokens
            self.outputConfig = OutputConfig(effort: effort)
            self.system = system
            self.messages = messages
        }

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case stream
            case thinking
            case outputConfig = "output_config"
            case system
            case messages
        }
    }
}
