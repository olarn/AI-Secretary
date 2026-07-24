import Foundation
import ToolAdapters

/// What the Secretary understood from a user message. Deliberately a small
/// closed set for this phase — no free-form command construction.
public enum Intent: Equatable, Sendable {
    /// Run a known read-only code operation, optionally against a named project.
    case codeTool(operation: CodeToolOperation, projectQuery: String?)
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

    public func classify(_ text: String) -> Intent {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .unknown(text: text) }

        if normalized == "help" || normalized == "?" || normalized.hasPrefix("help ") {
            return .help
        }

        for rule in rules where rule.keywords.contains(where: normalized.contains) {
            return .codeTool(operation: rule.operation, projectQuery: projectQuery(in: normalized))
        }

        return .unknown(text: text)
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
