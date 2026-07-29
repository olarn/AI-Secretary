import Foundation

/// A question the assistant asked, split into what it said and what you can
/// pick.
///
/// The options are found by an agreed marker rather than by reading the prose,
/// and that is the whole point. Assistants write lists constantly — three
/// candidate stacks, three steps they are about to take, three reasons
/// something failed — and a picker rendered over the wrong one is worse than
/// no picker at all. Two messages in a single afternoon of testing would have
/// been misread that way. So the model is asked to mark a real question, and
/// anything unmarked stays prose.
///
/// The marker is a fenced block, which is already invisible to nothing: it has
/// to be removed before rendering or it shows up as literal text under the
/// picker.
///
/// ```choices
/// Stateless stub — the same fixture every time
/// Stateful — a POST has to be visible to the next GET
/// ```
public struct MessageChoices: Equatable, Sendable {
    /// The message with the block taken out, ready to render.
    public let body: String
    /// What the person can pick, in the order given. Empty when the message
    /// asked nothing.
    public let options: [String]

    public var isAsking: Bool { !options.isEmpty }

    /// More than this and a keyboard list stops being quicker than typing.
    /// Extra options are dropped rather than the block rejected, so a
    /// long-winded question still offers its first few.
    public static let maximumOptions = 8

    static let fence = "```choices"

    public init(body: String, options: [String]) {
        self.body = body
        self.options = options
    }

    /// Splits a message. A message with no block comes back unchanged and with
    /// no options, which is the overwhelmingly common case.
    public static func parse(_ text: String) -> MessageChoices {
        guard text.contains(fence) else { return MessageChoices(body: text, options: []) }

        var body: [String] = []
        var options: [String] = []
        var insideBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !insideBlock, trimmed == fence {
                insideBlock = true
                continue
            }
            if insideBlock {
                // Any closing fence ends it. An unclosed block runs to the end
                // of the message rather than swallowing the rest as prose —
                // a reply cut off mid-stream still offers what arrived.
                if trimmed.hasPrefix("```") {
                    insideBlock = false
                    continue
                }
                let option = clean(trimmed)
                if !option.isEmpty { options.append(option) }
            } else {
                body.append(line)
            }
        }

        guard !options.isEmpty else {
            // A block with nothing in it isn't a question. Give back the
            // original so nothing is silently lost from the message.
            return MessageChoices(body: text, options: [])
        }

        return MessageChoices(
            body: trimmingBlankEdges(body).joined(separator: "\n"),
            options: Array(options.prefix(maximumOptions))
        )
    }

    /// Options are written as a plain line, but models reach for list markers
    /// out of habit; a leading bullet or number would otherwise be sent back as
    /// part of the answer.
    private static func clean(_ line: String) -> String {
        var text = line
        for marker in ["- ", "* ", "• "] where text.hasPrefix(marker) {
            text.removeFirst(marker.count)
            break
        }
        // "1. ", "2) " and so on.
        if let match = text.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            text.removeSubrange(match)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// The blank lines that surrounded the block are separators, not content.
    private static func trimmingBlankEdges(_ lines: [String]) -> [String] {
        var trimmed = lines
        while trimmed.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeFirst() }
        while trimmed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeLast() }
        return trimmed
    }
}
