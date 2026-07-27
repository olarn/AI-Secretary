import Foundation

/// A pipe table found in a reply.
public struct MarkdownTable: Equatable, Sendable {
    public let header: [String]
    public let rows: [[String]]

    public init(header: [String], rows: [[String]]) {
        self.header = header
        self.rows = rows
    }

    public var columnCount: Int { header.count }
}

/// One run of a message: either prose, or a table to lay out.
public enum TranscriptSegment: Equatable, Sendable {
    case text(String)
    case table(MarkdownTable)
}

/// Splits a reply into prose and tables.
///
/// SwiftUI's `Text` understands inline markdown but not tables, so a table
/// arrives as a wall of pipes and dashes. Pulling them out here lets the view
/// lay each one out properly — and, because a table is often wider than the
/// chat bubble, scroll it sideways on its own without the whole conversation
/// scrolling with it.
///
/// Deliberately forgiving: anything that isn't clearly a table stays prose. A
/// message is a model's output, not a document we control, and mangling normal
/// text that happens to contain a pipe would be worse than not styling a table.
public enum MarkdownTableParser {
    public static func segments(of text: String) -> [TranscriptSegment] {
        let lines = text.components(separatedBy: .newlines)
        var segments: [TranscriptSegment] = []
        var prose: [String] = []
        var index = 0

        func flushProse() {
            // Trailing blank lines around a table are separators, not content.
            while prose.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { prose.removeLast() }
            guard !prose.isEmpty else { return }
            segments.append(.text(prose.joined(separator: "\n")))
            prose = []
        }

        while index < lines.count {
            if let table = table(at: index, in: lines) {
                flushProse()
                segments.append(.table(table.value))
                index = table.nextIndex
                // A blank line straight after a table is spacing, not prose.
                if index < lines.count,
                   lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                }
            } else {
                prose.append(lines[index])
                index += 1
            }
        }
        flushProse()
        return segments
    }

    /// A table is a row of cells followed by a dashes-and-colons row with the
    /// same number of cells. Requiring both is what keeps ordinary prose
    /// containing a `|` from being swallowed.
    private static func table(at start: Int, in lines: [String]) -> (value: MarkdownTable, nextIndex: Int)? {
        guard start + 1 < lines.count,
              isRow(lines[start]),
              isSeparator(lines[start + 1])
        else { return nil }

        let header = cells(of: lines[start])
        guard !header.isEmpty, cells(of: lines[start + 1]).count == header.count else { return nil }

        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count, isRow(lines[index]) {
            rows.append(fit(cells(of: lines[index]), to: header.count))
            index += 1
        }
        return (MarkdownTable(header: header, rows: rows), index)
    }

    private static func isRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") && !trimmed.isEmpty
    }

    /// `---`, `:---`, `---:`, `:---:` — one per column.
    private static func isSeparator(_ line: String) -> Bool {
        let parts = cells(of: line)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty else { return false }
            let body = part.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    /// Splits on pipes, ignoring the optional outer ones. Escaped pipes inside a
    /// cell (`\|`) are honoured so a cell can contain one.
    private static func cells(of line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") { trimmed.removeLast() }

        var parts: [String] = []
        var current = ""
        var escaped = false
        for character in trimmed {
            if escaped {
                current.append(character == "|" ? "|" : character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts
    }

    /// Ragged rows are common in generated markdown; pad or trim so the grid
    /// stays rectangular rather than dropping cells on the floor.
    private static func fit(_ row: [String], to count: Int) -> [String] {
        if row.count == count { return row }
        if row.count > count { return Array(row.prefix(count)) }
        return row + Array(repeating: "", count: count - row.count)
    }
}
