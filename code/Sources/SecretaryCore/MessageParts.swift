/// One thing the thread shows for a reply.
///
/// A reply that contains a table or a fenced block is not one message any more:
/// the block leaves the bubble and arrives as its own message underneath, the
/// way a chat app sends an attachment separately. Boxes were being drawn inside
/// boxes, and a table already has a border, a background and its own sideways
/// scroll — a bubble around that is a second frame saying nothing.
public enum MessagePart: Equatable, Sendable {
    /// Prose, which goes in a bubble. Never empty.
    case prose([TranscriptSegment])
    /// A table or a fenced block, drawn on its own with no bubble around it.
    case block(TranscriptSegment)
}

/// Groups a reply's segments into the messages the thread will show.
///
/// Consecutive prose stays together — a paragraph split by nothing shouldn't
/// arrive as two bubbles — and every table and fenced block becomes its own
/// message. Prose that is only whitespace is dropped rather than shown as an
/// empty bubble, which is what a reply that opens with a table would otherwise
/// produce.
public func messageParts(of segments: [TranscriptSegment]) -> [MessagePart] {
    var parts: [MessagePart] = []
    var prose: [TranscriptSegment] = []

    func flushProse() {
        guard !prose.isEmpty else { return }
        parts.append(.prose(prose))
        prose = []
    }

    for segment in segments {
        switch segment {
        case .text(let body):
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            prose.append(segment)
        case .table, .code:
            flushProse()
            parts.append(.block(segment))
        }
    }
    flushProse()
    return parts
}
