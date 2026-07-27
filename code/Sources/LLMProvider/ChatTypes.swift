import Foundation

/// A single conversational turn sent to or received from the model.
public struct ChatMessage: Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// A model the assistant may talk to. Only the exact published IDs are valid —
/// an unknown string is rejected rather than sent to the API (which would 404).
public struct ChatModel: Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    public static let opus5 = ChatModel(id: "claude-opus-5", displayName: "Claude Opus 5")
    public static let sonnet5 = ChatModel(id: "claude-sonnet-5", displayName: "Claude Sonnet 5")
    public static let fable5 = ChatModel(id: "claude-fable-5", displayName: "Claude Fable 5")
    public static let opus48 = ChatModel(id: "claude-opus-4-8", displayName: "Claude Opus 4.8")
    public static let opus47 = ChatModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
    public static let haiku45 = ChatModel(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5")

    public static let known: [ChatModel] = [opus5, sonnet5, fable5, opus48, opus47, haiku45]

    /// Short names Claude Code itself accepts, so what works in the terminal
    /// works here. Each points at the current model of that family.
    static let aliases: [String: ChatModel] = [
        "opus": opus5,
        "sonnet": sonnet5,
        "fable": fable5,
        "haiku": haiku45
    ]

    /// Words that mean "don't choose for me" — the backend's own default wins.
    static let inheritWords: Set<String> = ["default", "auto", "inherit"]

    /// Resolves a user-supplied model identifier against the allowlist.
    /// Returns nil for an unknown name *and* for "default"; callers that need to
    /// tell those apart should check `inheritWords` first.
    public static func named(_ raw: String) -> ChatModel? {
        let needle = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let alias = aliases[needle] { return alias }
        return known.first { $0.id.lowercased() == needle }
    }

    public static func meansInherit(_ raw: String) -> Bool {
        inheritWords.contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

/// Reasoning-depth / token-spend control (`output_config.effort`).
public enum Effort: String, CaseIterable, Sendable {
    case low, medium, high, xhigh, max

    public static func named(_ raw: String) -> Effort? {
        Effort(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

public struct ChatUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// A tool the backend wanted to use but wasn't allowed to.
///
/// Claude Code has no mid-turn approval: an un-granted tool is refused and the
/// model is told so, which it then reports to the user. Surfacing the refusal
/// as an event is what lets the orchestration layer offer to widen permissions
/// and try again, instead of the user hitting a wall they can't act on.
public struct DeniedTool: Equatable, Sendable {
    /// Tool name as Claude Code reports it, e.g. `Write`, `Bash`.
    public let name: String
    /// What it was going to act on — a path, or the command — for display.
    public let target: String?
    /// Permission rule that would allow this, in Claude Code's syntax.
    public let rule: String

    public init(name: String, target: String?, rule: String) {
        self.name = name
        self.target = target
        self.rule = rule
    }

    /// One line a human can decide on.
    public var summary: String {
        guard let target, !target.isEmpty else { return name }
        return "\(name): \(target)"
    }
}

/// Events surfaced from a streamed reply. The provider maps the raw Anthropic
/// SSE event types onto this small, UI-agnostic set.
public enum ChatStreamEvent: Equatable, Sendable {
    /// The backend was refused a tool. Only Claude Code emits this.
    case toolDenied(DeniedTool)
    /// The model began thinking (adaptive thinking). No visible text yet.
    case thinking
    /// A chunk of assistant text.
    case textDelta(String)
    /// The turn finished. `stopReason == "refusal"` means the model declined.
    case completed(stopReason: String?, usage: ChatUsage?)
}

public enum ChatError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case network(String)
    /// Claude Code isn't installed, or we couldn't find it.
    case claudeCodeNotFound
    /// The Claude Code process failed to start or exited badly.
    case claudeCodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Claude API key is set. Add one in Settings to start chatting."
        case .http(let status, let message):
            return "Claude API error (\(status)): \(message)"
        case .network(let detail):
            return "Network error: \(detail)"
        case .claudeCodeNotFound:
            return """
            Claude Code isn't installed on this Mac — I work by driving your own \
            copy of it. Install it and sign in, then try again.
            """
        case .claudeCodeFailed(let detail):
            return "Claude Code failed: \(detail)"
        }
    }
}
