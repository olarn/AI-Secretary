import FunctionalCore
import Foundation
import ToolAdapters

public enum Intent: Equatable, Sendable {
    case codeTool(operation: CodeToolOperation, projectQuery: Option<String>)
    case fileTool(operation: FileOperation, projectQuery: Option<String>)
    case understandFile(request: FileUnderstanding, projectQuery: Option<String>)
    case help
    case unknown(text: String)
}

public final class RuleBasedIntentClassifier {
    public init() {}

    private struct Rule {
        let operation: CodeToolOperation
        let keywords: [String]
    }

    private let rules: [Rule] = [
        Rule(operation: .diffStat, keywords: ["diff", "changes", "changed files"]),
        Rule(operation: .recentLog, keywords: ["log", "commits", "history", "recent commit"]),
        Rule(operation: .currentBranch, keywords: ["branch", "which branch", "current branch"]),
        Rule(operation: .status, keywords: ["status", "state of", "what's changed", "whats changed"])
    ]

    private let strongReadPrefixes = ["show contents of ", "show file ", "open file "]
    private let weakReadPrefixes = ["read ", "cat "]
    private let strongListPrefixes = ["list files ", "show files "]
    private let weakListPrefixes = ["list ", "files ", "ls ", "dir "]
    private let listExact: Set<String> = ["list", "ls", "dir", "files", "list files", "show files"]

    private let understandPrefixes: [(String, FileUnderstanding.Task)] = [
        ("summarize ", .summarize),
        ("summarise ", .summarize),
        ("summary of ", .summarize),
        ("explain ", .explain),
        ("analyze ", .analyze),
        ("analyse ", .analyze),
        ("review ", .review),
        ("describe ", .describe)
    ]

    public func classify(_ text: String) -> Intent {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = original.lowercased()
        guard !normalized.isEmpty else { return .unknown(text: text) }

        if normalized == "help" || normalized == "?" || normalized.hasPrefix("help ") {
            return .help
        }

        let fileOperationsAreCheckedFirstSoReadTheLogFileIsNotCaughtByTheLogKeyword =
            fileIntent(original: original)
        return fileOperationsAreCheckedFirstSoReadTheLogFileIsNotCaughtByTheLogKeyword
            .getOrElse(codeToolIntent(normalized).getOrElse(.unknown(text: text)))
    }

    static func containsWord(_ keyword: String, in text: String) -> Bool {
        guard !keyword.isEmpty else { return false }
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: keyword, range: searchRange) {
            let beforeOK = found.lowerBound == text.startIndex
                || !isWordCharacter(text[text.index(before: found.lowerBound)])
            let afterOK = found.upperBound == text.endIndex
                || !isWordCharacter(text[found.upperBound])
            if beforeOK && afterOK { return true }
            guard found.upperBound < text.endIndex else { return false }
            searchRange = text.index(after: found.lowerBound)..<text.endIndex
        }
        return false
    }

    private func codeToolIntent(_ normalized: String) -> Option<Intent> {
        guard isSingleSentence(normalized) else { return .none() }
        return Option.fromOptional(
            rules.first { rule in
                rule.keywords.contains { Self.containsWord($0, in: normalized) }
            }
        )
        .map { Intent.codeTool(operation: $0.operation, projectQuery: self.projectQuery(in: normalized)) }^
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    private func fileIntent(original: String) -> Option<Intent> {
        let (head, project) = splitProject(original)
        let headLower = head.lowercased()

        let understanding = understandIntent(head: head, headLower: headLower)
            .map { Intent.understandFile(request: $0, projectQuery: project) }^
        if understanding.isDefined { return understanding }

        for prefix in strongReadPrefixes where headLower.hasPrefix(prefix) {
            let path = cleanPath(String(head.dropFirst(prefix.count)))
            guard !path.isEmpty else { return .none() }
            return .some(.fileTool(operation: .readFile(relativePath: path), projectQuery: project))
        }
        for prefix in weakReadPrefixes where headLower.hasPrefix(prefix) {
            let path = cleanPath(String(head.dropFirst(prefix.count)))
            guard !path.isEmpty else { return .none() }
            guard project.isDefined || looksLikePath(path) else { return .none() }
            return .some(.fileTool(operation: .readFile(relativePath: path), projectQuery: project))
        }

        if listExact.contains(headLower) {
            return .some(.fileTool(operation: .listDirectory(relativePath: "."), projectQuery: project))
        }
        for prefix in strongListPrefixes where headLower.hasPrefix(prefix) {
            let path = cleanPath(String(head.dropFirst(prefix.count)))
            return .some(
                .fileTool(
                    operation: .listDirectory(relativePath: path.isEmpty ? "." : path),
                    projectQuery: project
                )
            )
        }
        for prefix in weakListPrefixes where headLower.hasPrefix(prefix) {
            let path = cleanPath(String(head.dropFirst(prefix.count)))
            guard project.isDefined || looksLikePath(path) else { return .none() }
            return .some(
                .fileTool(
                    operation: .listDirectory(relativePath: path.isEmpty ? "." : path),
                    projectQuery: project
                )
            )
        }

        return .none()
    }

    private func understandIntent(head: String, headLower: String) -> Option<FileUnderstanding> {
        if headLower.hasPrefix("what does ") {
            var body = cleanPath(String(head.dropFirst("what does ".count)))
            for suffix in [" do", " contain", " say"] where body.lowercased().hasSuffix(suffix) {
                body = String(body.dropLast(suffix.count))
                break
            }
            let path = cleanPath(body)
            return looksLikePath(path)
                ? .some(FileUnderstanding(relativePath: path, task: .explain))
                : .none()
        }

        for (prefix, task) in understandPrefixes where headLower.hasPrefix(prefix) {
            var body = String(head.dropFirst(prefix.count))
            for article in ["the file ", "the ", "this ", "my "] where body.lowercased().hasPrefix(article) {
                body = String(body.dropFirst(article.count))
                break
            }
            let path = cleanPath(body)
            guard looksLikePath(path) else { return .none() }
            return .some(FileUnderstanding(relativePath: path, task: task))
        }

        return .none()
    }

    private func looksLikePath(_ s: String) -> Bool {
        if s.contains("/") { return true }
        if s.hasPrefix(".") && !s.dropFirst().contains(" ") { return true }
        if let dot = s.lastIndex(of: "."), dot != s.startIndex {
            let ext = s[s.index(after: dot)...]
            return !ext.isEmpty && ext.count <= 8 && ext.allSatisfy { $0.isLetter || $0.isNumber }
        }
        return false
    }

    private func splitProject(_ text: String) -> (head: String, project: Option<String>) {
        splitAtProjectMarker(text)
    }

    private func cleanPath(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!\"'`"))
            .trimmingCharacters(in: .whitespaces)
    }

    private func projectQuery(in text: String) -> Option<String> {
        splitAtProjectMarker(text).project
    }
}

func looksLikeProjectName(_ candidate: String) -> Bool {
    guard !candidate.isEmpty, candidate.count <= 60 else { return false }
    guard !candidate.contains(where: { ",.();:".contains($0) }) else { return false }
    return candidate.split(separator: " ").count <= 5
}

func isSingleSentence(_ text: String) -> Bool {
    let characters = Array(text)
    for (offset, character) in characters.enumerated() where ".?!".contains(character) {
        let rest = characters[(offset + 1)...]
        guard let next = rest.first, next.isWhitespace else { continue }
        if rest.contains(where: { !$0.isWhitespace }) { return false }
    }
    return true
}

func splitAtProjectMarker(_ text: String) -> (head: String, project: Option<String>) {
    let named = projectMarkerRanges(in: text)
        .map { range in
            (
                head: String(text[text.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                tail: String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?.!\"'"))
            )
        }
        .filter { looksLikeProjectName($0.tail) }

    return named.last.map { ($0.head, Option.some($0.tail)) } ?? (text, .none())
}

private func projectMarkerRanges(in text: String) -> [Range<String.Index>] {
    [" in ", " for ", " on "]
        .flatMap { marker in occurrences(of: marker, in: text) }
        .sorted { $0.lowerBound < $1.lowerBound }
}

private func occurrences(of marker: String, in text: String) -> [Range<String.Index>] {
    var found: [Range<String.Index>] = []
    var searchRange = text.startIndex..<text.endIndex
    while let range = text.range(of: marker, options: [.caseInsensitive], range: searchRange) {
        found.append(range)
        guard range.lowerBound < text.endIndex else { break }
        searchRange = text.index(after: range.lowerBound)..<text.endIndex
    }
    return found
}
