import Foundation

public struct InstructionPlan: Equatable, Sendable {
    public let relativePath: String
    public let fingerprint: String
    public let steps: [String]

    public init(relativePath: String, fingerprint: String, steps: [String]) {
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.steps = steps
    }

    public var isEmpty: Bool { steps.isEmpty }
}

public struct PlanBlock: Equatable, Sendable {
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
            return PlanBlock(body: text, steps: [])
        }
        return PlanBlock(body: trimmingBlankEdges(body).joined(separator: "\n"), steps: steps)
    }

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
