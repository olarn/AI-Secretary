import FunctionalCore
import Foundation

public struct MarkdownTable: Equatable, Sendable {
    public let header: [String]
    public let rows: [[String]]

    public init(header: [String], rows: [[String]]) {
        self.header = header
        self.rows = rows
    }

    public var columnCount: Int { header.count }
}

public struct CodeBlock: Equatable, Sendable {
    public let language: String?
    public let code: String

    public init(language: String?, code: String) {
        self.language = language
        self.code = code
    }
}

public enum TranscriptSegment: Equatable, Sendable {
    case text(String)
    case table(MarkdownTable)
    case code(CodeBlock)
}

public enum MarkdownTableParser {
    public static func segments(of text: String) -> [TranscriptSegment] {
        let lines = text.components(separatedBy: .newlines)
        var segments: [TranscriptSegment] = []
        var prose: [String] = []
        var index = 0

        func flushProse() {
            while prose.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { prose.removeLast() }
            guard !prose.isEmpty else { return }
            segments.append(.text(prose.joined(separator: "\n")))
            prose = []
        }

        while index < lines.count {
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

    private static func isSeparator(_ line: String) -> Bool {
        let parts = cells(of: line)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty else { return false }
            let body = part.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

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

    static func codeBlock(at index: Int, in lines: [String]) -> (value: CodeBlock, nextIndex: Int)? {
        let opening = lines[index].trimmingCharacters(in: .whitespaces)
        guard opening.hasPrefix("```") else { return nil }

        let label = opening.dropFirst(3).trimmingCharacters(in: .whitespaces)
        let isTheAppsOwnChoicesMarkerStrippedBeforeRendering = label.lowercased() == "choices"
        guard !isTheAppsOwnChoicesMarkerStrippedBeforeRendering else { return nil }

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

        let aFenceWithNothingInItIsPunctuationNotCode =
            !code.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !aFenceWithNothingInItIsPunctuationNotCode else {
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

    private static func fit(_ row: [String], to count: Int) -> [String] {
        if row.count == count { return row }
        if row.count > count { return Array(row.prefix(count)) }
        return row + Array(repeating: "", count: count - row.count)
    }
}
