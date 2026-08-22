import Foundation

public struct MessageChoices: Equatable, Sendable {
    public let body: String
    public let options: [String]

    public var isAsking: Bool { !options.isEmpty }

    public static let maximumOptions = 8

    static let numberedListMarker = #"^\d+[.)]\s+"#

    static let fence = "```choices"

    public init(body: String, options: [String]) {
        self.body = body
        self.options = options
    }

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
                let anyClosingFenceEndsTheBlock = trimmed.hasPrefix("```")
                if anyClosingFenceEndsTheBlock {
                    insideBlock = false
                    continue
                }
                let option = clean(trimmed)
                if !option.isEmpty { options.append(option) }
            } else {
                body.append(line)
            }
        }

        let aBlockWithNothingInItIsNotAQuestion = options.isEmpty
        guard !aBlockWithNothingInItIsNotAQuestion else {
            return MessageChoices(body: text, options: [])
        }

        return MessageChoices(
            body: trimmingBlankEdges(body).joined(separator: "\n"),
            options: Array(options.prefix(maximumOptions))
        )
    }

    private static func clean(_ line: String) -> String {
        var text = line
        for marker in ["- ", "* ", "• "] where text.hasPrefix(marker) {
            text.removeFirst(marker.count)
            break
        }
        if let match = text.range(of: numberedListMarker, options: .regularExpression) {
            text.removeSubrange(match)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func trimmingBlankEdges(_ lines: [String]) -> [String] {
        var trimmed = lines
        while trimmed.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeFirst() }
        while trimmed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeLast() }
        return trimmed
    }
}
