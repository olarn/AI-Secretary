import Foundation

/// Remembers how each message was broken into boxes, so a reply arriving token
/// by token doesn't re-parse the whole conversation on every token.
///
/// Why it earns its keep: the transcript is one list, and a token landing in
/// the last message rebuilds all of it. Splitting one long message into prose,
/// tables and fenced blocks measured at about 2ms, so a conversation with ten
/// long messages in it was paying twenty for every token of the eleventh —
/// which is what the scrolling stutter was made of. Only the message currently
/// growing actually needs parsing; the ones above it are finished and cannot
/// have changed.
///
/// Keyed by message, and holding the exact text it parsed. Same text, same
/// answer — `parts(id:text:)` is a memo of a deterministic function, not a
/// second source of truth, so a stale entry is impossible rather than merely
/// unlikely: if the text differs by one character it is parsed again.
public final class MessagePartsCache {
    private var remembered: [UUID: (text: String, parts: [MessagePart])] = [:]

    /// How many parses were avoided and how many were done. For tests — the
    /// point of this type is a count, and a count is the only way to assert it.
    public private(set) var hits = 0
    public private(set) var misses = 0

    public init() {}

    /// The boxes for one message: markers stripped, pasted rows recognised as
    /// tables, prose grouped.
    public func parts(id: UUID, text: String) -> [MessagePart] {
        if let hit = remembered[id], hit.text == text {
            hits += 1
            return hit.parts
        }
        misses += 1
        let parsed = messageParts(of: DelimitedTableParser.segments(of: displayBody(of: text)))
        remembered[id] = (text, parsed)
        return parsed
    }

    /// Drops everything not in the conversation any more — starting a new
    /// conversation, or loading an old one, replaces the lot.
    public func keepingOnly(_ ids: Set<UUID>) {
        remembered = remembered.filter { ids.contains($0.key) }
    }
}

/// A message with the markers meant for the app rather than the reader taken
/// out.
///
/// The Secretary already strips a loop block from a finished reply, but not
/// from a failed one, and a reply still streaming has yet to be stripped at all
/// — neither should put a fenced block on screen.
public func displayBody(of text: String) -> String {
    LoopBlock.parse(MessageChoices.parse(text).body).body
}
