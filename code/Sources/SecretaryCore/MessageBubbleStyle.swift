/// How one transcript entry is laid out in the thread.
///
/// The conversation reads like a chat app: what you said is tucked against one
/// edge, what the Secretary said against the other, and neither runs the full
/// width. Which side an entry takes and how much room it may have are decisions,
/// so they live here rather than in the view — `AISecretaryApp` is never linked
/// into the test bundle.
public struct MessageBubbleStyle: Equatable, Sendable {
    public enum Side: Equatable, Sendable { case leading, trailing }

    /// Which edge the bubble sits against.
    public let side: Side
    /// The user's own messages, which get the tinted fill.
    public let isMine: Bool
    /// Whether the entry is drawn as a bubble at all. Activity is a report of
    /// what happened rather than something anyone said, and stays the
    /// full-width dashed box it already was — bubbling it would make it look
    /// like part of the answer, which is the one thing its styling exists to
    /// avoid.
    public let isBubble: Bool
    /// The Secretary is named above its bubble because the app has several
    /// personas and which one answered matters. "You" is not shown: the side
    /// already says it, and a 1:1 chat that labels your own messages reads as a
    /// transcript rather than a conversation.
    public let showsSpeakerName: Bool
}

public func messageBubbleStyle(
    speaker: TranscriptEntry.Speaker,
    kind: TranscriptEntry.Kind
) -> MessageBubbleStyle {
    guard kind == .message else {
        return MessageBubbleStyle(side: .leading, isMine: false, isBubble: false, showsSpeakerName: false)
    }
    let mine = speaker == .user
    return MessageBubbleStyle(
        side: mine ? .trailing : .leading,
        isMine: mine,
        isBubble: true,
        showsSpeakerName: !mine
    )
}

/// The empty lane left on the far side of a bubble, so a message is visibly
/// tucked against its own edge instead of spanning the panel.
///
/// A share of the panel's width, not a constant: the chat is resizable in both
/// axes, and a fixed gutter is either invisible when the panel is wide or eats
/// the message when it is narrow. Floored so a very narrow panel still shows
/// the offset, and capped so a very wide one doesn't squeeze a table into a
/// column.
public func messageBubbleGutter(panelWidth: Double) -> Double {
    min(max(panelWidth * 0.16, 28), 160)
}
