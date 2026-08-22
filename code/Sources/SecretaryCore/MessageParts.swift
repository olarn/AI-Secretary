public enum MessagePart: Equatable, Sendable {
    case prose([TranscriptSegment])
    case block(TranscriptSegment)
}

public func copyText(of part: MessagePart) -> String {
    switch part {
    case .prose(let segments):
        return segments
            .compactMap { segment -> String? in
                if case .text(let body) = segment { return body }
                return nil
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    case .block(.code(let block)):
        return block.code
    case .block(.table(let table)):
        return markdownText(of: table)
    case .block(.text(let body)):
        return body
    }
}

public func markdownText(of table: MarkdownTable) -> String {
    let row = { (cells: [String]) in "| " + cells.joined(separator: " | ") + " |" }
    let divider = row(Array(repeating: "---", count: table.header.count))
    return ([row(table.header), divider] + table.rows.map(row)).joined(separator: "\n")
}

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
