import FunctionalCore
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

/// A fenced block of code, or something the model handed over verbatim.
public struct CodeBlock: Equatable, Sendable {
    /// What the fence was labelled with — `swift`, `json`, and so on. Absent
    /// when the fence carried no label.
    public let language: String?
    public let code: String

    public init(language: String?, code: String) {
        self.language = language
        self.code = code
    }
}

/// One run of a message: prose, a table to lay out, or code to show verbatim.
public enum TranscriptSegment: Equatable, Sendable {
    case text(String)
    case table(MarkdownTable)
    case code(CodeBlock)
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
            // Code first. A fenced block can contain pipes, dashes, anything —
            // it is verbatim by definition — so looking for tables inside one
            // would tear it apart.
            if let block = codeBlock(at: index, in: lines) {
                flushProse()
                segments.append(.code(block.value))
                index = block.nextIndex
                if index < lines.count,
                   lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                }
            } else if let table = table(at: index, in: lines).toOptional() {
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
    private static func table(at start: Int, in lines: [String]) -> Option<(value: MarkdownTable, nextIndex: Int)> {
        guard start + 1 < lines.count,
              isRow(lines[start]),
              isSeparator(lines[start + 1])
        else { return .none() }

        let header = cells(of: lines[start])
        guard !header.isEmpty, cells(of: lines[start + 1]).count == header.count else { return .none() }

        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count, isRow(lines[index]) {
            rows.append(fit(cells(of: lines[index]), to: header.count))
            index += 1
        }
        return .some((MarkdownTable(header: header, rows: rows), index))
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

    /// A fenced block starting at `index`, if there is one.
    ///
    /// Fences have to be pulled out before anything else touches the message.
    /// The inline markdown renderer is given `.inlineOnlyPreservingWhitespace`
    /// so a stray character can't restructure a reply — but that also means it
    /// swallows the fence and reflows the contents, which is how a JSON sample
    /// arrived in the chat as `json { "iso": ... }` on one line.
    ///
    /// An unclosed fence still yields its block: replies stream in, and the
    /// closing line may not have arrived yet.
    static func codeBlock(at index: Int, in lines: [String]) -> (value: CodeBlock, nextIndex: Int)? {
        let opening = lines[index].trimmingCharacters(in: .whitespaces)
        guard opening.hasPrefix("```") else { return nil }

        let label = opening.dropFirst(3).trimmingCharacters(in: .whitespaces)
        // ```choices is the app's own marker for a question, handled elsewhere
        // and already removed before rendering. Never draw it as code.
        guard label.lowercased() != "choices" else { return nil }

        var code: [String] = []
        var cursor = index + 1
        while cursor < lines.count {
            if lines[cursor].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                cursor += 1
                break
            }
            code.append(lines[cursor])
            cursor += 1
        }

        // A fence with nothing in it is punctuation, not code.
        guard code.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }

        return (
            CodeBlock(
                language: label.isEmpty ? nil : label,
                code: trimmingBlankEdges(code).joined(separator: "\n")
            ),
            cursor
        )
    }

    private static func trimmingBlankEdges(_ lines: [String]) -> [String] {
        var trimmed = lines
        while trimmed.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeFirst() }
        while trimmed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed.removeLast() }
        return trimmed
    }

    /// Ragged rows are common in generated markdown; pad or trim so the grid
    /// stays rectangular rather than dropping cells on the floor.
    private static func fit(_ row: [String], to count: Int) -> [String] {
        if row.count == count { return row }
        if row.count > count { return Array(row.prefix(count)) }
        return row + Array(repeating: "", count: count - row.count)
    }
}
