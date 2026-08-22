import FunctionalCore
import Foundation

public struct LoopBlock: Equatable, Sendable {
    public let body: String
    public let request: LoopCommand.Request?

    static let fence = "```loop"

    public init(body: String, request: LoopCommand.Request?) {
        self.body = body
        self.request = request
    }

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
            return LoopBlock(body: text, request: nil)
        }

        if LoopCommand.stopWords.contains(first.lowercased()) {
            return LoopBlock(body: trimmingBlankEdges(body).joined(separator: "\n"), request: .stop)
        }

        let head = droppingTheLabelThatReadsBetterInAPrompt(
            "every",
            from: droppingTheLabelThatReadsBetterInAPrompt("every:", from: first)
        )
        let note = lines.dropFirst().joined(separator: "\n")

        return LoopCommand.parseInterval(head).fold(
            { _ in
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
