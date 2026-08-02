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
    /// what happened rather than something anyone said, so it is drawn as a
    /// system message instead: narrowed from both sides and centred, which is
    /// neither speaker's side.
    public let isBubble: Bool
    /// Every message is named — "Me" for yours, the persona's name for the
    /// Secretary's — with the time beside it. The side already says who spoke,
    /// but a thread kept across launches needs to say *when*, and a name to hang
    /// the time on costs nothing.
    public let showsSpeakerName: Bool
    /// Which corner of the bubble the name and time sit in. Against the
    /// bubble's own outer edge in both cases, so the two headers mirror each
    /// other rather than both hugging the left.
    public let headerSide: Side
    /// Only the Secretary's answers can be copied. Yours you already have, and
    /// a copy button on every line you typed is clutter on the side of the
    /// thread that never needs it.
    public let showsCopyButton: Bool
}

public func messageBubbleStyle(
    speaker: TranscriptEntry.Speaker,
    kind: TranscriptEntry.Kind
) -> MessageBubbleStyle {
    guard kind == .message else {
        return MessageBubbleStyle(
            side: .leading,
            isMine: false,
            isBubble: false,
            showsSpeakerName: false,
            headerSide: .leading,
            showsCopyButton: false
        )
    }
    let mine = speaker == .user
    return MessageBubbleStyle(
        side: mine ? .trailing : .leading,
        isMine: mine,
        isBubble: true,
        showsSpeakerName: true,
        headerSide: mine ? .trailing : .leading,
        showsCopyButton: !mine
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

/// How far a system message — the activity report — is pulled in from *both*
/// edges.
///
/// Narrower than the conversation on either side and centred between them, so
/// it reads as the app talking about itself rather than as either speaker's
/// turn. Smaller than the bubble gutter on purpose: it is inset from both sides
/// at once, and a system note that ends up narrower than the messages it
/// explains is harder to read for no gain.
public func systemMessageInset(panelWidth: Double) -> Double {
    min(max(panelWidth * 0.06, 10), 48)
}
