import FunctionalCore
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
    /// Absent for an unknown name *and* for "default"; callers that need to
    /// tell those apart should check `meansInherit` first.
    public static func named(_ raw: String) -> Option<ChatModel> {
        let needle = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return Option.fromOptional(aliases[needle])
            .orElse(Option.fromOptional(known.first { $0.id.lowercased() == needle }))
    }

    public static func meansInherit(_ raw: String) -> Bool {
        inheritWords.contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

/// Reasoning-depth / token-spend control (`output_config.effort`).
public enum Effort: String, CaseIterable, Sendable {
    case low, medium, high, xhigh, max

    public static func named(_ raw: String) -> Option<Effort> {
        Option.fromOptional(Effort(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()))
    }
}

/// What one turn cost.
///
/// The cache counts are separate fields rather than folded into `inputTokens`
/// because they are priced differently, and because leaving them out is not a
/// rounding error: a turn reported as 2 in / 5 out really moved 11,768 cache
/// writes and 24,436 cache reads.
public struct ChatUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    /// Tokens written into the prompt cache.
    public let cacheWriteTokens: Int
    /// Tokens served from the prompt cache.
    public let cacheReadTokens: Int
    /// What the traffic would bill on the API. Reported even on a subscription,
    /// where nothing is charged per token.
    public let costUSD: Double
    /// The model's context window, when the backend says.
    public let contextWindow: Int?

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int = 0,
        cacheReadTokens: Int = 0,
        costUSD: Double = 0,
        contextWindow: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.contextWindow = contextWindow
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
    public let target: Option<String>
    /// Permission rule that would allow this, in Claude Code's syntax.
    public let rule: String

    public init(name: String, target: Option<String>, rule: String) {
        self.name = name
        self.target = target
        self.rule = rule
    }

    /// One line a human can decide on.
    public var summary: String {
        target.filter { !$0.isEmpty }^
            .fold({ self.name }, { "\(self.name): \($0)" })
    }
}

/// Something the assistant is doing right now.
///
/// Not the model's reasoning — Claude Code returns thinking blocks whose text
/// is empty (`display: "omitted"` is the default on Opus 5 and there is no CLI
/// flag to change it, and the raw chain of thought is never returned on that
/// family at all). What can be shown is the activity itself: that it is
/// thinking, and which tool it reached for with what argument. In practice
/// that is what "what is it doing?" actually means.
public struct AgentActivity: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case thinking, tool }

    public let id = UUID()
    public let kind: Kind
    public let detail: String

    public init(kind: Kind, detail: String) {
        self.kind = kind
        self.detail = detail
    }

    public static func == (lhs: AgentActivity, rhs: AgentActivity) -> Bool {
        lhs.kind == rhs.kind && lhs.detail == rhs.detail
    }
}

/// Events surfaced from a streamed reply. The provider maps the raw Anthropic
/// SSE event types onto this small, UI-agnostic set.
public enum ChatStreamEvent: Equatable, Sendable {
    /// The backend was refused a tool. Only Claude Code emits this.
    case toolDenied(DeniedTool)
    /// Progress worth showing while the user waits. Only Claude Code emits this.
    case activity(AgentActivity)
    /// The model began thinking (adaptive thinking). No visible text yet.
    case thinking
    /// A chunk of assistant text.
    case textDelta(String)
    /// The model began a fresh block of text.
    ///
    /// A turn is not one piece of writing: the model says something, reaches
    /// for a tool, says something else, and each of those is its own content
    /// block. The deltas carry no hint of where one ends, so joining them gave
    /// `…/grill-with-docs เองได้เลยนะNo existing note on this.` — two thoughts
    /// with not even a space between them, because there was never a character
    /// there to begin with. This is that missing character.
    case textBlockBegan
    /// The turn finished. `stopReason == "refusal"` means the model declined.
    case completed(stopReason: Option<String>, usage: Option<ChatUsage>)
}

public enum ChatError: Error, Equatable, Sendable, LocalizedError {
    case http(status: Int, message: String)
    case network(String)
    /// Claude Code isn't installed, or we couldn't find it.
    case claudeCodeNotFound
    /// The Claude Code process failed to start or exited badly.
    case claudeCodeFailed(String)

    public var errorDescription: String? {
        switch self {
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
            // Read for a cause rather than shown raw: "Claude Code failed:" in
            // front of a stack trace leaves the reader to work out whether they
            // are logged out, out of usage, or offline — three different things
            // to do about it.
            return ClaudeCodeFailure.classify(detail).message(detail: detail)
        }
    }
}

/// A streamed reply: events on the right rail, a typed failure on the left.
///
/// `AsyncStream` rather than `AsyncThrowingStream` — a thrown `Error` is
/// untyped, so every consumer had to guess what it might be. Here the only
/// thing that can arrive is a `ChatError`, and the stream simply ends after it.
public typealias ChatStream = AsyncStream<Either<ChatError, ChatStreamEvent>>
