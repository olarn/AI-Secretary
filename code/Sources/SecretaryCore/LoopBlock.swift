import FunctionalCore
import Foundation

/// A loop the assistant asked to start, or stop, on its own.
///
/// The point of the feature is that nobody has to type: someone running a
/// workshop asks "keep track of where we are" once, with both hands otherwise
/// busy. So the assistant needs a way to set the timer itself — but a timer
/// that starts because a sentence *sounded* like a request would be exactly the
/// hidden autonomy this app is built to avoid. Hence a marker, the same shape
/// as `MessageChoices`: the request is unmistakable, and everything unmarked
/// stays prose.
///
/// ```loop
/// every: 10m
/// บอกว่าตอนนี้ถึงหัวข้อไหน และถัดไปคืออะไร
/// ```
///
/// Starting one is announced in the conversation with how to stop it, and the
/// limits in `LoopSchedule` apply whoever asked — so the worst case is a
/// visible, bounded, one-click-reversible timer rather than an app that quietly
/// talks to itself.
public struct LoopBlock: Equatable, Sendable {
    /// The message with the block taken out, ready to render.
    public let body: String
    /// What the assistant asked for, if it asked.
    public let request: LoopCommand.Request?

    static let fence = "```loop"

    public init(body: String, request: LoopCommand.Request?) {
        self.body = body
        self.request = request
    }

    /// Splits a message. Anything without a block comes back untouched, which
    /// is nearly every message.
    public static func parse(_ text: String) -> LoopBlock {
        guard text.contains(fence) else { return LoopBlock(body: text, request: nil) }

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
        guard let first = lines.first else {
            // An empty block asks for nothing. Hand back the original rather
            // than quietly dropping part of the message.
            return LoopBlock(body: text, request: nil)
        }

        if LoopCommand.stopWords.contains(first.lowercased()) {
            return LoopBlock(body: trimmingBlankEdges(body).joined(separator: "\n"), request: .stop)
        }

        // `every: 10m` reads better in a prompt than a bare `10m`, so the label
        // is accepted and dropped.
        let head = first
            .replacingOccurrences(of: "every:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "every", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        let note = lines.dropFirst().joined(separator: "\n")

        return LoopCommand.parseInterval(head).fold(
            { _ in
                // An unreadable or out-of-bounds interval leaves the message
                // whole and starts nothing: better a reply that mentions a
                // timer than a timer nobody asked for at a rate nobody chose.
                LoopBlock(body: text, request: nil)
            },
            { interval in
                LoopBlock(
                    body: trimmingBlankEdges(body).joined(separator: "\n"),
                    request: .start(interval: interval, note: note)
                )
            }
        )
    }

    private static func trimmingBlankEdges(_ lines: [String]) -> [String] {
        var trimmed = lines
        while trimmed.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeFirst() }
        while trimmed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeLast() }
        return trimmed
    }
}
