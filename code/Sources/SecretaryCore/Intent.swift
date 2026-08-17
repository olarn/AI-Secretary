import FunctionalCore
import Foundation
import ToolAdapters

/// What the Secretary understood from a user message. Deliberately a small
/// closed set for this sprint — no free-form command construction.
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

/// Rule-based classifier: keyword matching only, no model call. Anything that
/// doesn't clearly match a known operation returns `.unknown`, so the assistant
/// never invents an action from ambiguous text.
///
/// A class because it holds the rule tables, but it is not a seam: what the
/// Secretary takes is the function `classify`, not a protocol. There was a
/// one-method `IntentClassifying` here purely so a test could substitute it,
/// which is a closure wearing a protocol's clothes.
public final class RuleBasedIntentClassifier {
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
        // isn't captured by the "log" keyword. Both answers stay inside
        // `Option` until the last line, where the fallback is chat.
        return fileIntent(original: original)
            .getOrElse(codeToolIntent(normalized).getOrElse(.unknown(text: text)))
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

    /// The first Git rule whose keywords appear in the text, as an `Option` so
    /// `classify` can chain it rather than unwrap it. `first(where:)` says what
    /// the `for … where … { return }` it replaced was doing: first match wins.
    private func codeToolIntent(_ normalized: String) -> Option<Intent> {
        // The armour `fileIntent` has had all along, finally on this side too.
        // A git keyword only means a command when the message is shaped like
        // one; in prose it is just a word. See `isSingleSentence`.
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

    /// Parses "read <path> in <project>", "list [<path>] in <project>", etc.
    /// Returns nil if the text isn't a file command, so it falls through to Git
    /// or chat. A path is never turned into an absolute path here — it stays a
    /// project-relative string for the adapter to resolve and bound-check.
    private func fileIntent(original: String) -> Option<Intent> {
        let (head, project) = splitProject(original)
        let headLower = head.lowercased()

        // Understand: checked first so "summarize README.md" doesn't fall into
        // the read path and merely dump the file.
        let understanding = understandIntent(head: head, headLower: headLower)
            .map { Intent.understandFile(request: $0, projectQuery: project) }^
        if understanding.isDefined { return understanding }

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
        splitAtProjectMarker(text)
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
        splitAtProjectMarker(text).project
    }
}

// MARK: - Prose is not a command

/// Whether this could be the name of a registered project.
///
/// Guards the `" in "` / `" for "` / `" on "` split, which used to hand back
/// everything after the marker whatever it was. A 300-character English
/// paragraph about debt management (2026-08-17) contained "legal **status**"
/// and "specializing **in** non-performing…", so it was read as `git status`
/// in a project named by the remaining ~50 words, resolved to nothing, and the
/// turn ended with *"No registered project matches …"* — **the model was never
/// called at all**, which reads to the person as the app going quiet.
///
/// The three conditions are what separates a name from a sentence:
///
/// - **60 characters.** Long enough for the longest folder name anyone has
///   registered here (`AI-Secretary`, `Second-Brain`, `TISCO - AI Sharing`)
///   with room to spare; far shorter than the ~300-character paragraph that
///   caused this.
/// - **5 words.** A folder name is a name. The paragraph's tail ran to about
///   fifty, and even a generous multi-word name stops well before five.
/// - **No `, . ( ) ; :`.** Sentence punctuation. A path may carry a dot, but
///   this is not a path — the file rules have `looksLikePath` for that, and a
///   trailing `.` or `?` is already trimmed before this is asked.
///
/// Both numbers are ceilings on a *name*, not tuned thresholds: the failing
/// input was an order of magnitude past either, so neither is close to the line.
func looksLikeProjectName(_ candidate: String) -> Bool {
    guard !candidate.isEmpty, candidate.count <= 60 else { return false }
    guard !candidate.contains(where: { ",.();:".contains($0) }) else { return false }
    return candidate.split(separator: " ").count <= 5
}

/// Whether the text is one sentence, with no boundary inside it.
///
/// The second guard, and the one that catches prose the first cannot: a short
/// single sentence with "legal status" and " in " in it still classifies wrong,
/// and a paragraph with a plausible short tail after its last marker still
/// reaches the git rules. A boundary is `.`, `?` or `!` followed by whitespace
/// and then more text — `README.md` and a trailing `?` are both untouched by
/// that, and a real command is one sentence by construction.
///
/// **Structural on purpose, and it must stay that way.** A word count would be
/// a number, and the Settings-panel lesson is that a number can always be
/// exceeded; "one sentence" has no dial to turn. There is deliberately no
/// "unless it says `git`" shortcut either — that reopens the same hole for any
/// paragraph mentioning git, and this case never needed it.
func isSingleSentence(_ text: String) -> Bool {
    let characters = Array(text)
    for (offset, character) in characters.enumerated() where ".?!".contains(character) {
        let rest = characters[(offset + 1)...]
        guard let next = rest.first, next.isWhitespace else { continue }
        if rest.contains(where: { !$0.isWhitespace }) { return false }
    }
    return true
}

/// Splits "<command> in/for/on <project>" at the **last** marker whose tail
/// could be a name.
///
/// Last, not first: a project name sits at the end of the request, while an
/// English sentence can contain "in" anywhere. The previous version looped over
/// the markers in the order `[" in ", " for ", " on "]` and returned the first
/// marker that appeared *at all*, which is not even the earliest one in the
/// text — "specializing in …" won over every later, better candidate.
///
/// Shared by the file rules and the git rules. It was two near-identical
/// copies, and guarding one of them would have left the other still able to
/// hand a whole paragraph to the file adapter as a path.
///
/// Searches `text` itself, case-insensitively. Searching a lowercased copy and
/// then slicing the original is undefined — a `String.Index` belongs to the
/// string it came from. It happened to work for ASCII and crashed on the first
/// Thai message that contained " On ": "Range requires lowerBound <= upperBound".
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

/// Every occurrence of every marker, in the order they appear in the text.
private func projectMarkerRanges(in text: String) -> [Range<String.Index>] {
    [" in ", " for ", " on "]
        .flatMap { marker in occurrences(of: marker, in: text) }
        .sorted { $0.lowerBound < $1.lowerBound }
}

private func occurrences(of marker: String, in text: String) -> [Range<String.Index>] {
    var found: [Range<String.Index>] = []
    var searchRange = text.startIndex..<text.endIndex
    // Resumes one character past the *start* of the hit, not past its end, so
    // overlapping markers in " on in " are both seen.
    while let range = text.range(of: marker, options: [.caseInsensitive], range: searchRange) {
        found.append(range)
        guard range.lowerBound < text.endIndex else { break }
        searchRange = text.index(after: range.lowerBound)..<text.endIndex
    }
    return found
}
