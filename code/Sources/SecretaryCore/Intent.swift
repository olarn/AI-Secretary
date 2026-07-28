import FunctionalCore
import Foundation
import ToolAdapters

/// What the Secretary understood from a user message. Deliberately a small
/// closed set for this phase — no free-form command construction.
public enum Intent: Equatable, Sendable {
    /// Run a known read-only code operation, optionally against a named project.
    case codeTool(operation: CodeToolOperation, projectQuery: Option<String>)
    /// Read a directory listing or a text file inside a named project.
    case fileTool(operation: FileOperation, projectQuery: Option<String>)
    /// Read a file *and send it to the model* to summarise, explain, analyse,
    /// review or describe. Separate from `fileTool` because it leaves the machine.
    case understandFile(request: FileUnderstanding, projectQuery: Option<String>)
    /// Understood, but nothing to execute.
    case help
    /// Not understood; the Secretary will say so rather than guess.
    case unknown(text: String)
}

public protocol IntentClassifying: AnyObject {
    func classify(_ text: String) -> Intent
}

/// Rule-based classifier: keyword matching only, no model call. Anything that
/// doesn't clearly match a known operation returns `.unknown`, so the assistant
/// never invents an action from ambiguous text.
public final class RuleBasedIntentClassifier: IntentClassifying {
    public init() {}

    private struct Rule {
        let operation: CodeToolOperation
        let keywords: [String]
    }

    /// Ordered: more specific phrasings are checked before broader ones.
    private let rules: [Rule] = [
        Rule(operation: .diffStat, keywords: ["diff", "changes", "changed files"]),
        Rule(operation: .recentLog, keywords: ["log", "commits", "history", "recent commit"]),
        Rule(operation: .currentBranch, keywords: ["branch", "which branch", "current branch"]),
        Rule(operation: .status, keywords: ["status", "state of", "what's changed", "whats changed"])
    ]

    /// "Strong" prefixes name a file operation unambiguously ("show file …"), so
    /// they classify as a file op regardless of what follows. "Weak" prefixes are
    /// also common chat openers ("read me a poem"), so they only count as a file
    /// op when the message is project-scoped or the argument looks path-like —
    /// otherwise the message falls through to normal conversation.
    private let strongReadPrefixes = ["show contents of ", "show file ", "open file "]
    private let weakReadPrefixes = ["read ", "cat "]
    private let strongListPrefixes = ["list files ", "show files "]
    private let weakListPrefixes = ["list ", "files ", "ls ", "dir "]
    private let listExact: Set<String> = ["list", "ls", "dir", "files", "list files", "show files"]

    /// Verbs that mean "tell me about this file". Every one of them is a common
    /// conversational opener too ("explain how actors work", "review my plan"),
    /// so unlike the read/list verbs these *always* require a path-like argument
    /// — a project scope alone is not enough to make them a file operation.
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

        // File operations are checked before Git rules so "read the log file"
        // isn't captured by the "log" keyword.
        if let file = fileIntent(original: original).toOptional() {
            return file
        }

        for rule in rules where rule.keywords.contains(where: { Self.containsWord($0, in: normalized) }) {
            return .codeTool(operation: rule.operation, projectQuery: projectQuery(in: normalized))
        }

        return .unknown(text: text)
    }

    /// Whether `keyword` appears in `text` as a whole word or phrase, rather
    /// than buried inside a longer one.
    ///
    /// A plain `contains` matched "log" inside "login", so asking whether a web
    /// page was logged in ran `git log` instead — and then failed, because the
    /// tool path needs a registered project while ordinary chat does not. Any
    /// keyword short enough to be useful is short enough to hide inside another
    /// word: "diff" in "different", "status" in "statuses", "ls" in almost
    /// anything.
    ///
    /// Only ASCII letters and digits continue a word, because every keyword is
    /// ASCII. Thai is written without spaces, so an English term inside a Thai
    /// sentence usually has none around it — "ขอดูlogหน่อย" is the word `log`
    /// with Thai on either side, and treating any letter as continuing the word
    /// would miss it.
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

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    /// Parses "read <path> in <project>", "list [<path>] in <project>", etc.
    /// Returns nil if the text isn't a file command, so it falls through to Git
    /// or chat. A path is never turned into an absolute path here — it stays a
    /// project-relative string for the adapter to resolve and bound-check.
    private func fileIntent(original: String) -> Option<Intent> {
        let (head, project) = splitProject(original)
        let headLower = head.lowercased()

        // Understand: checked first so "summarize README.md" doesn't fall into
        // the read path and merely dump the file.
        if let understanding = understandIntent(head: head, headLower: headLower).toOptional() {
            return .some(.understandFile(request: understanding, projectQuery: project))
        }

        // Read: explicit phrasing always counts; weak verbs need a scope or a
        // path-like argument so they don't capture ordinary chat.
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

        // List: a bare "list"/"ls"/"dir" is an unambiguous command. Everything
        // else follows the same weak-verb guard as read.
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

    /// Parses "summarize <path>", "explain <path>", "what does <path> do".
    /// Returns nil unless the argument actually looks like a path, so ordinary
    /// requests ("explain how actors work") stay conversation.
    private func understandIntent(head: String, headLower: String) -> Option<FileUnderstanding> {
        // "what does <path> do?" — the one non-prefix phrasing worth supporting.
        if headLower.hasPrefix("what does ") {
            // Trailing punctuation comes off first so the "… do?" suffix matches.
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
            // "summarize the file src/Main.swift" — drop a leading article so the
            // path heuristic sees the path itself.
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

    /// Heuristic for "this argument is a filesystem path, not prose": it contains
    /// a slash, ends in a short extension, or is a leading-dot dotfile.
    private func looksLikePath(_ s: String) -> Bool {
        if s.contains("/") { return true }
        if s.hasPrefix(".") && !s.dropFirst().contains(" ") { return true }
        if let dot = s.lastIndex(of: "."), dot != s.startIndex {
            let ext = s[s.index(after: dot)...]
            return !ext.isEmpty && ext.count <= 8 && ext.allSatisfy { $0.isLetter || $0.isNumber }
        }
        return false
    }

    /// Splits a "… in/for/on <project>" suffix off the command, preserving the
    /// original case of both halves. Returns (command, projectQuery?).
    private func splitProject(_ text: String) -> (head: String, project: Option<String>) {
        for marker in [" in ", " for ", " on "] {
            // Search `text` itself, case-insensitively. Searching a lowercased
            // copy and then slicing the original is undefined — a String.Index
            // belongs to the string it came from. It happened to work for ASCII
            // and crashed on the first Thai message that contained " On ":
            // "Range requires lowerBound <= upperBound".
            guard let range = text.range(of: marker, options: [.caseInsensitive]) else { continue }
            let head = String(text[text.startIndex..<range.lowerBound])
            let tail = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "?.!\"'"))
            if !tail.isEmpty {
                return (head.trimmingCharacters(in: .whitespacesAndNewlines), .some(tail))
            }
        }
        return (text, .none())
    }

    private func cleanPath(_ raw: String) -> String {
        // Note: no "." here — dotfiles like ".env" must keep their leading dot.
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!\"'`"))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Extracts a project name following "in"/"for"/"on", e.g.
    /// "git status in AI-Secretary". Returns nil when no such phrase appears.
    private func projectQuery(in text: String) -> Option<String> {
        for marker in [" in ", " for ", " on "] {
            guard let range = text.range(of: marker) else { continue }
            let tail = text[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "?.!\"'"))
            if !tail.isEmpty { return .some(tail) }
        }
        return .none()
    }
}
