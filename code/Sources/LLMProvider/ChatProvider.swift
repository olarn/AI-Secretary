import Foundation

/// The boundary the Secretary talks to for conversational replies. Streaming so
/// the UI can render tokens as they arrive; injectable so orchestration can be
/// tested with a fake that emits canned events and needs no network or key.
public protocol ChatProvider: Sendable {
    /// `model` and `effort` are optional: nil means the user hasn't chosen, so
    /// the backend's own configured default should stand. Overriding it would
    /// quietly give someone a different model than the one they set up.
    func stream(
        messages: [ChatMessage],
        model: ChatModel?,
        effort: Effort?,
        maxTokens: Int,
        system: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}
