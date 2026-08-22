import FunctionalCore
import Foundation

public enum DelimitedTableParser {
    static let delimiters: [Character] = [",", "\t", ";"]

    static let minimumRows = 2

    public static func segments(of text: String) -> [TranscriptSegment] {
        MarkdownTableParser.segments(of: text).flatMap { segment -> [TranscriptSegment] in
            guard case .text(let prose) = segment else { return [segment] }
            return delimitedSegments(of: prose)
        }
    }

    static func delimitedSegments(of text: String) -> [TranscriptSegment] {
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
            if let found = table(at: index, in: lines).toOptional() {
                flushProse()
                segments.append(.table(found.value))
                index = found.nextIndex
                continue
            }
            prose.append(lines[index])
            index += 1
        }
        flushProse()
        return segments
    }

    static func table(at start: Int, in lines: [String]) -> Option<(value: MarkdownTable, nextIndex: Int)> {
        guard start < lines.count else { return .none() }
        for delimiter in delimiters {
            let first = fields(of: lines[start], delimiter: delimiter)
            guard first.count > 1 else { continue }

            guard looksLikeData(first) else { continue }

            var rows = [first]
            var index = start + 1
            while index < lines.count {
                let next = fields(of: lines[index], delimiter: delimiter)
                guard next.count == first.count, looksLikeData(next) else { break }
                rows.append(next)
                index += 1
            }
            guard rows.count >= minimumRows else { continue }
            let everyCellIsEmptySoItIsPunctuationThatLinesUpNotData =
                !rows.contains { $0.contains { !$0.isEmpty } }
            guard !everyCellIsEmptySoItIsPunctuationThatLinesUpNotData else { continue }
            return .some((MarkdownTable(header: rows[0], rows: Array(rows.dropFirst())), index))
        }
        return .none()
    }

    static func groupsANumber(at index: Int, in characters: [Character]) -> Bool {
        guard characters[index] == "," , index > 0, index + 1 < characters.count else { return false }
        return characters[index - 1].isNumber && characters[index + 1].isNumber
    }

    static func looksLikeData(_ fields: [String]) -> Bool {
        if let last = fields.last?.trimmingCharacters(in: .whitespaces),
           let final = last.last,
           ".!?".contains(final) {
            return false
        }
        return !fields.contains { $0.split(whereSeparator: \.isWhitespace).count > 8 }
    }

    static func fields(of line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                let isADoubledQuoteInsideAQuotedFieldMeaningOneQuote =
                    quoted && index + 1 < characters.count && characters[index + 1] == "\""
                if isADoubledQuoteInsideAQuotedFieldMeaningOneQuote {
                    current.append("\"")
                    index += 2
                    continue
                }
                quoted.toggle()
            } else if character == delimiter, !quoted, !groupsANumber(at: index, in: characters) {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        characters = []
        return fields
    }
}
