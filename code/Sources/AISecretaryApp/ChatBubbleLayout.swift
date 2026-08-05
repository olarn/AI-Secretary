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

    /// Bumped each time the bubble is shown, so the message box can take the
    /// caret.
    ///
    /// A count rather than a flag, and a count rather than `onAppear`: the view
    /// is built once and then hidden and shown by changing the window's alpha,
    /// so `onAppear` fires at launch and never again, and a `Bool` set true a
    /// second time is not a change SwiftUI will act on. Showing the bubble twice
    /// has to read as two separate events.
    private(set) var focusRequests: Int = 0

    func requestInputFocus() { focusRequests += 1 }
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
