import Observation

/// Tracks which side of the chat bubble the speech-bubble tail should be on.
/// Updated by `AppDelegate` whenever the character (and therefore the bubble)
/// is repositioned, so the bubble can flip sides to stay on-screen while the
/// tail keeps pointing naturally at the character.
@Observable
final class ChatBubbleLayout {
    var isMirrored: Bool = false
}
