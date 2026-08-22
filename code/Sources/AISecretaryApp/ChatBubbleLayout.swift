import SwiftUI
import Observation

@Observable
final class ChatBubbleLayout {
    var isMirrored: Bool = false
    var isFlippedVertically: Bool = false

    private(set) var focusRequests: Int = 0

    func requestInputFocus() { focusRequests += 1 }
}

struct TranscriptTailKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
