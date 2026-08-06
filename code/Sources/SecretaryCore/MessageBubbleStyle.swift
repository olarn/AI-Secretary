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
    /// what happened rather than something anyone said, so it is drawn as bare
    /// dimmed text instead — no box — starting in the same column as the
    /// Secretary's words.
    public let isBubble: Bool
    /// Every message is named — "Me" for yours, the persona's name for the
    /// Secretary's — with the time beside it, on a line above the boxes rather
    /// than inside one: a turn split into three boxes has one speaker, and a
    /// name inside the first box reads as a caption on that box alone. The side
    /// already says who spoke, but a thread kept across launches needs to say
    /// *when*, and a name to hang the time on costs nothing.
    public let showsSpeakerName: Bool
    /// A turn that ended in an error rather than an answer. Drawn on the
    /// Secretary's side, because that is where an answer would have been, but
    /// in a warning colour and headed as a failure — the app reporting that it
    /// couldn't get an answer, not the persona saying something.
    public let isFailure: Bool
    /// Only the Secretary's answers can be copied. Yours you already have, and
    /// a copy button on every line you typed is clutter on the side of the
    /// thread that never needs it.
    public let showsCopyButton: Bool
    /// The "Working" heading over a line of running commentary.
    ///
    /// Only activity earns it. A divider shares activity's plain unattributed
    /// look but is not work in progress, and the heading is a claim about the
    /// app's state, not a style: "Working / New conversation." says something
    /// is running when the whole point of the line is that nothing is.
    public let showsWorkingLabel: Bool
}

public func messageBubbleStyle(
    speaker: TranscriptEntry.Speaker,
    kind: TranscriptEntry.Kind
) -> MessageBubbleStyle {
    switch kind {
    // A divider is drawn like the running commentary — plain, unattributed, no
    // bubble — because it is the same sort of thing: the app saying where it
    // is, not the persona saying anything.
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
        // Copyable like an answer: the text of a failure is the thing most
        // worth pasting somewhere — a terminal, a bug report — of anything in
        // the thread.
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
