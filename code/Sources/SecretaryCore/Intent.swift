import Foundation
import ToolAdapters

/// What the Secretary understood from a user message. Deliberately a small
/// closed set for this phase — no free-form command construction.
public enum Intent: Equatable, Sendable {
    /// Run a known read-only code operation, optionally against a named project.
    case codeTool(operation: CodeToolOperation, projectQuery: String?)
    /// Read a directory listing or a text file inside a named project.
    case fileTool(operation: FileOperation, projectQuery: String?)
    /// Read a file *and send it to the model* to summarise, explain, analyse,
    /// review or describe. Separate from `fileTool` because it leaves the machine.
    case understandFile(request: FileUnderstanding, projectQuery: String?)
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
        if let file = fileIntent(original: original) {
            return file
        }

        for rule in rules where rule.keywords.contains(where: normalized.contains) {
            return .codeTool(operation: rule.operation, projectQuery: projectQuery(in: normalized))
        }

        return .unknown(text: text)
    }

    /// Parses "read <path> in <project>", "list [<path>] in <project>", etc.
    /// Returns nil if the text isn't a file command, so it falls through to Git
    /// or chat. A path is never turned into an absolute path here — it stays a
    /// project-relative string for the adapter to resolve and bound-check.
    private func fileIntent(original: String) -> Intent? {
        let (head, project) = splitProject(original)
        let headLower = head.lowercased()

        // Understand: checked first so "summarize README.md" doesn't fall into
        // the read path and merely dump the file.
        if let understanding = understandIntent(head: head, headLower: headLower) {
            return .understandFile(request: understanding, projectQuery: project)
        }

        // Read: explicit phrasing always counts; weak verbs need a scope or a
        // path-like argument so they don't capture ordinary chat.
        for prefix in strongReadPrefixes where headLower.hasPrefix(prefix) {
            let path = cleanPath(String(head.dropFirst(prefix.count)))
            guard !path.isEmpty else { return nil }
            return .fileTool(operation: .readFile(relativePath: path), projectQuery: project)
        }
        for prefix in weakReadPrefixes where headLower.hasPrefix(prefix) {
            let path = cleanPath(String(head.dropFirst(prefix.count)))
            guard !path.isEmpty else { return nil }
            guard project != nil || looksLikePath(path) else { return nil }
            return .fileTool(operation: .readFile(relativePath: path), projectQuery: project)
        }

        // List: a bare "list"/"ls"/"dir" is an unambiguous command. Everything
        // else follows the same weak-verb guard as read.
        if listExact.contains(headLower) {
            return .fileTool(operation: .listDirectory(relativePath: "."), projectQuery: project)
        }
        for prefix in strongListPrefixes where headLower.hasPrefix(prefix) {
            let path = cleanPath(String(head.dropFirst(prefix.count)))
            return .fileTool(operation: .listDirectory(relativePath: path.isEmpty ? "." : path),
                             projectQuery: project)
        }
        for prefix in weakListPrefixes where headLower.hasPrefix(prefix) {
            let path = cleanPath(String(head.dropFirst(prefix.count)))
            guard project != nil || looksLikePath(path) else { return nil }
            return .fileTool(operation: .listDirectory(relativePath: path.isEmpty ? "." : path),
                             projectQuery: project)
        }

        return nil
    }

    /// Parses "summarize <path>", "explain <path>", "what does <path> do".
    /// Returns nil unless the argument actually looks like a path, so ordinary
    /// requests ("explain how actors work") stay conversation.
    private func understandIntent(head: String, headLower: String) -> FileUnderstanding? {
        // "what does <path> do?" — the one non-prefix phrasing worth supporting.
        if headLower.hasPrefix("what does ") {
            // Trailing punctuation comes off first so the "… do?" suffix matches.
            var body = cleanPath(String(head.dropFirst("what does ".count)))
            for suffix in [" do", " contain", " say"] where body.lowercased().hasSuffix(suffix) {
                body = String(body.dropLast(suffix.count))
                break
            }
            let path = cleanPath(body)
            return looksLikePath(path) ? FileUnderstanding(relativePath: path, task: .explain) : nil
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
            guard looksLikePath(path) else { return nil }
            return FileUnderstanding(relativePath: path, task: task)
        }

        return nil
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
    private func splitProject(_ text: String) -> (head: String, project: String?) {
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
                return (head.trimmingCharacters(in: .whitespacesAndNewlines), tail)
            }
        }
        return (text, nil)
    }

    private func cleanPath(_ raw: String) -> String {
        // Note: no "." here — dotfiles like ".env" must keep their leading dot.
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!\"'`"))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Extracts a project name following "in"/"for"/"on", e.g.
    /// "git status in AI-Secretary". Returns nil when no such phrase appears.
    private func projectQuery(in text: String) -> String? {
        for marker in [" in ", " for ", " on "] {
            guard let range = text.range(of: marker) else { continue }
            let tail = text[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "?.!\"'"))
            if !tail.isEmpty { return tail }
        }
        return nil
    }
}
