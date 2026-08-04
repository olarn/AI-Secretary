import Foundation

/// Splitting a ```something block off the end of a reply.
///
/// The shape is the app's one way of letting the assistant ask for an action:
/// marked, or it didn't ask. Guessing from prose would turn every sentence
/// containing "I'll keep an eye on that" into a running background job — and
/// the model writes sentences like that constantly.
///
/// `LoopBlock` and `InfoWindowBlock` predate this and each carry their own copy
/// of the walk; they are left alone rather than churned, but nothing new should
/// add a fourth.
enum FencedBlock {
    /// The message with the block removed, plus the non-empty lines that were
    /// inside it. `nil` when there is no block, which is nearly every message.
    static func split(_ text: String, fence: String) -> (body: String, lines: [String])? {
        guard text.contains(fence) else { return nil }

        var body: [String] = []
        var block: [String] = []
        var insideBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !insideBlock, trimmed == fence {
                insideBlock = true
                continue
            }
            if insideBlock {
                if trimmed.hasPrefix("```") {
                    insideBlock = false
                    continue
                }
                block.append(trimmed)
            } else {
                body.append(line)
            }
        }

        let lines = block.filter { !$0.isEmpty }
        // An empty block asks for nothing. Hand back the original rather than
        // showing a reply with a hole where the marker was.
        guard !lines.isEmpty else { return nil }
        return (trimmingBlankEdges(body).joined(separator: "\n"), lines)
    }

    private static func trimmingBlankEdges(_ lines: [String]) -> [String] {
        var trimmed = lines
        while trimmed.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeFirst() }
        while trimmed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeLast() }
        return trimmed
    }
}
