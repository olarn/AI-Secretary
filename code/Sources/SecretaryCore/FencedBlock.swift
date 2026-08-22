import Foundation

enum FencedBlock {
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
        let theBlockAsksForNothing = lines.isEmpty
        guard !theBlockAsksForNothing else { return nil }
        return (trimmingBlankEdges(body).joined(separator: "\n"), lines)
    }

    private static func trimmingBlankEdges(_ lines: [String]) -> [String] {
        var trimmed = lines
        while trimmed.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeFirst() }
        while trimmed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeLast() }
        return trimmed
    }
}
