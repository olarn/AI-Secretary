import FunctionalCore
import Foundation

/// Pasted rows — CSV or tab-separated — recognised as a table.
///
/// The reason this exists: handing over data is the point of Phase 11, and the
/// two ways a person has it to hand are a file and their clipboard. A pasted
/// CSV rendered as prose is a wall of commas the person cannot check, and the
/// whole risk of data entry is entering the wrong thing — so it goes on screen
/// as a grid, in the same view a markdown table already uses, and they can see
/// their own columns before anything is typed into anyone's web app.
///
/// Recognition, not parsing of a format. Everything below is about *whether*
/// this run of lines is a table; the fields are split simply and quoted commas
/// are respected because a name like "Smith, J." is the ordinary case, not an
/// edge one.
public enum DelimitedTableParser {
    /// The delimiters worth guessing between. Semicolons are what a European
    /// spreadsheet exports; tabs are what a copied selection carries.
    static let delimiters: [Character] = [",", "\t", ";"]

    /// Fewest lines that can be a table: a header and one row. One line of
    /// commas is a sentence.
    static let minimumRows = 2

    /// Splits a message into prose and every table in it — pipe tables first,
    /// then pasted rows inside what is left.
    ///
    /// Order matters: a markdown table's separator row (`---|---`) is itself
    /// consistent enough to look delimited, so the pipe parser gets first look.
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

    /// The longest run of lines from `start` that all split the same way.
    ///
    /// "The same way" is the whole test, and it is deliberately strict: every
    /// line in the run has to yield the same number of fields, and there has to
    /// be more than one field. Two consecutive prose lines almost never carry
    /// an identical number of commas, and the cost of being wrong is a
    /// paragraph drawn as a grid — so being wrong is made hard rather than
    /// impossible.
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
            // A run where nothing is filled in — ",,," repeated — is punctuation
            // that happens to line up, not data.
            guard rows.contains(where: { $0.contains { !$0.isEmpty } }) else { continue }
            return .some((MarkdownTable(header: rows[0], rows: Array(rows.dropFirst())), index))
        }
        return .none()
    }

    /// Whether a line's fields read as data rather than as a sentence that
    /// happens to contain commas.
    ///
    /// Matching field counts alone was not enough, and the case that broke it
    /// is ordinary writing: "I went to the shop, and then home." over "It was
    /// raining, so I hurried." is two lines of two fields each, and it was
    /// drawn as a two-column grid. Two signals separate them — a sentence ends
    /// in a full stop, and a cell is short. Both are about the *last* field or
    /// the length, neither about the content, so nothing here has to know what
    /// the data is about.
    ///
    /// The cost, stated plainly: a column of long notes that end in full stops
    /// stays prose. That is the safe way round — an unstyled CSV is still
    /// readable, a paragraph in a grid is not.
    static func looksLikeData(_ fields: [String]) -> Bool {
        if let last = fields.last?.trimmingCharacters(in: .whitespaces),
           let final = last.last,
           ".!?".contains(final) {
            return false
        }
        return !fields.contains { $0.split(whereSeparator: \.isWhitespace).count > 8 }
    }

    /// One line's fields. Quotes are honoured because a value with a comma in
    /// it — an address, a name written surname-first — is what quoting is for,
    /// and splitting through it would silently shift every later column.
    static func fields(of line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                // A doubled quote inside a quoted field is one quote.
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 2
                    continue
                }
                quoted.toggle()
            } else if character == delimiter, !quoted {
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
