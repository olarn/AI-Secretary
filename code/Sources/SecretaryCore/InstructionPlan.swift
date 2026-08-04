import Foundation

/// The steps a file asks for, as the model read them back.
///
/// There is deliberately no parser here for the file's own format. The charter
/// asks this to work with prose, numbered steps, a diagram, or a LangGraph
/// graph — four parsers, none of which would ever cover the fifth thing
/// somebody writes. The model reads the document and answers in one shape;
/// this is that shape, and it is the only thing the rest of the app sees.
///
/// It is a plan, not a permission. Every step still runs through the ordinary
/// approval path when it acts, and the whole plan is shown before any of it
/// starts.
public struct InstructionPlan: Equatable, Sendable {
    public let relativePath: String
    /// What the file said when the plan was made. The run is pinned to this.
    public let fingerprint: String
    public let steps: [String]

    public init(relativePath: String, fingerprint: String, steps: [String]) {
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.steps = steps
    }

    public var isEmpty: Bool { steps.isEmpty }
}

/// A message with a ```plan block in it, split apart.
///
/// Same shape as `LoopBlock` and `MessageChoices`, and for the same reason:
/// steps guessed out of prose would turn every list the model writes into a
/// plan waiting to be run. Marked or not a plan at all.
///
/// ```plan
/// Pull the latest changes
/// Run the test suite
/// ```
public struct PlanBlock: Equatable, Sendable {
    /// The message with the block taken out, ready to render.
    public let body: String
    public let steps: [String]

    static let fence = "```plan"

    public init(body: String, steps: [String]) {
        self.body = body
        self.steps = steps
    }

    public static func parse(_ text: String) -> PlanBlock {
        guard text.contains(fence) else { return PlanBlock(body: text, steps: []) }

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

        let steps = block.compactMap(strippingBullet)
        guard !steps.isEmpty else {
            // An empty block asks for nothing. Hand the message back whole
            // rather than showing a reply with a hole in it.
            return PlanBlock(body: text, steps: [])
        }
        return PlanBlock(body: trimmingBlankEdges(body).joined(separator: "\n"), steps: steps)
    }

    /// "1. Pull" and "- Pull" and "Pull" are the same step. The model is asked
    /// for bare lines and mostly obliges, but a numbered list is the natural
    /// way to write steps and shouldn't produce steps that begin with a digit.
    private static func strippingBullet(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        if let dot = text.firstIndex(where: { $0 == "." || $0 == ")" }),
           text[text.startIndex..<dot].allSatisfy(\.isNumber),
           dot > text.startIndex {
            text = String(text[text.index(after: dot)...])
        } else if text.hasPrefix("- ") || text.hasPrefix("* ") || text.hasPrefix("• ") {
            text = String(text.dropFirst(2))
        }

        let cleaned = text.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func trimmingBlankEdges(_ lines: [String]) -> [String] {
        var trimmed = lines
        while trimmed.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeFirst() }
        while trimmed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeLast() }
        return trimmed
    }
}
