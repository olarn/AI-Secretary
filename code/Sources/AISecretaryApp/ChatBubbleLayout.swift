import SwiftUI
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

/// Reports where the bottom of the transcript content sits inside the scroll
/// view's coordinate space, so the panel can tell whether the reader is at the
/// bottom. macOS 14 has no scroll-position API; this is the way to measure it.
struct TranscriptBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
