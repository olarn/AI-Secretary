public struct MessageBubbleStyle: Equatable, Sendable {
    public enum Side: Equatable, Sendable { case leading, trailing }

    public let side: Side
    public let isMine: Bool
    public let isBubble: Bool
    public let showsSpeakerName: Bool
    public let isFailure: Bool
    public let showsCopyButton: Bool
    public let showsWorkingLabel: Bool
}

public func messageBubbleStyle(
    speaker: TranscriptEntry.Speaker,
    kind: TranscriptEntry.Kind
) -> MessageBubbleStyle {
    switch kind {
    case .activity, .divider:
        return MessageBubbleStyle(
            side: .leading,
            isMine: false,
            isBubble: false,
            showsSpeakerName: false,
            isFailure: false,
            showsCopyButton: false,
            showsWorkingLabel: kind == .activity
        )
    case .failure:
        return MessageBubbleStyle(
            side: .leading,
            isMine: false,
            isBubble: true,
            showsSpeakerName: true,
            isFailure: true,
            showsCopyButton: true,
            showsWorkingLabel: false
        )
    case .message:
        let mine = speaker == .user
        return MessageBubbleStyle(
            side: mine ? .trailing : .leading,
            isMine: mine,
            isBubble: true,
            showsSpeakerName: true,
            isFailure: false,
            showsCopyButton: !mine,
            showsWorkingLabel: false
        )
    }
}

public func messageBubbleGutter(panelWidth: Double) -> Double {
    min(max(panelWidth * 0.16, 28), 160)
}
