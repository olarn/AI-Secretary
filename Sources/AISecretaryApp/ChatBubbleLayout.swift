import Observation

/// Tracks which side/orientation the chat bubble's tail should be on.
/// Updated by `AppDelegate` whenever the character (and therefore the
/// bubble) is repositioned, so the bubble can flip horizontally and/or
/// vertically to stay on-screen while the tail keeps pointing naturally at
/// the character.
@Observable
final class ChatBubbleLayout {
    var isMirrored: Bool = false
    var isFlippedVertically: Bool = false
}
