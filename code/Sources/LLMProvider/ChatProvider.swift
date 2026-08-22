import FunctionalCore
import Foundation

public protocol ChatProvider: Sendable {
    func stream(
        messages: [ChatMessage],
        model modelChosenByTheUser: Option<ChatModel>,
        effort effortChosenByTheUser: Option<Effort>,
        maxTokens: Int,
        system: Option<String>
    ) -> ChatStream
}
