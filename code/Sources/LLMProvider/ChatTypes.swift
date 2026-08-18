import FunctionalCore
import Foundation

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

    /// Absent for an unknown name *and* for "default" — callers that need to
    /// tell those apart must check `meansInherit` first.
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
    public let cacheWriteTokens: Int
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
    /// The permission rules that would allow this, in Claude Code's syntax.
    ///
    /// Plural since 0.13.219, and that was the bug: one refused `Bash` call can
    /// need several, because Claude Code requires every operation in a `&&`
    /// chain to be permitted separately. A single rule covered the first one
    /// and the retry was refused again — see `bashPermissionRules`.
    public let rules: [String]

    public init(name: String, target: Option<String>, rules: [String]) {
        self.name = name
        self.target = target
        self.rules = rules
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
/// Whose work a piece of activity is.
///
/// Carried as data rather than spelled into `detail`, so the view has nothing to
/// parse and cannot get the answer wrong by reading a prefix. The associated
/// value is the id of the `Agent` tool call that started the sub-agent, which is
/// what the stream tags its inner turns with (`parent_tool_use_id`).
public enum ActivityOrigin: Equatable, Sendable {
    case main
    case subagent(String)
}

public struct AgentActivity: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case thinking, tool }

    public let id = UUID()
    public let kind: Kind
    public let detail: String
    /// Defaulted, so every existing caller and test reads unchanged — the
    /// sub-agent dimension was added without rewriting the ones that never had
    /// one.
    public let origin: ActivityOrigin

    public init(kind: Kind, detail: String, origin: ActivityOrigin = .main) {
        self.kind = kind
        self.detail = detail
        self.origin = origin
    }

    public static func == (lhs: AgentActivity, rhs: AgentActivity) -> Bool {
        lhs.kind == rhs.kind && lhs.detail == rhs.detail && lhs.origin == rhs.origin
    }
}

/// A sub-agent the character has started, as it is worth showing.
///
/// Claude Code reports these on its own — `task_started` and `task_progress`
/// `system` lines carry every field here — so none of it is inferred from tool
/// calls. Measured against Claude Code 2.1.234; see the sprint record for the
/// captured stream.
public struct SubagentTask: Equatable, Sendable, Identifiable {
    /// The CLI's `task_id`. Stable for the life of the sub-agent, which is what
    /// makes progress lines attachable to the thing they are about.
    public let id: String
    /// `subagent_type` — "general-purpose" and friends.
    public let kind: String
    /// The CLI's own `description`, which is a sentence about what it is doing
    /// right now and changes as it goes.
    public let detail: String
    /// The tool it reached for last, when it has reached for one.
    public let lastTool: Option<String>

    public init(id: String, kind: String, detail: String, lastTool: Option<String> = .none()) {
        self.id = id
        self.kind = kind
        self.detail = detail
        self.lastTool = lastTool
    }
}

/// How a sub-agent ended.
///
/// `summary` is the CLI's own one-line answer from `task_notification`, which is
/// why the character can report an outcome without waiting for the launching
/// tool's result to come back and without asking the model to say it again.
public struct SubagentOutcome: Equatable, Sendable {
    public let id: String
    public let status: String
    public let summary: String

    public init(id: String, status: String, summary: String) {
        self.id = id
        self.status = status
        self.summary = summary
    }
}

/// Events surfaced from a streamed reply. The provider maps the raw Anthropic
/// SSE event types onto this small, UI-agnostic set.
public enum ChatStreamEvent: Equatable, Sendable {
    /// Only Claude Code emits this.
    case toolDenied(DeniedTool)
    /// Only Claude Code emits this.
    case activity(AgentActivity)
    /// A sub-agent started. Only Claude Code emits these three.
    case subagentStarted(SubagentTask)
    /// It is still going, and this is what it is doing now. Also the heartbeat
    /// the liveness rule measures from — the CLI sends one per step, so silence
    /// is meaningful.
    case subagentProgress(SubagentTask)
    /// It finished, with its own summary of the answer.
    case subagentFinished(SubagentOutcome)
    /// Adaptive thinking began. Carries no visible text — there is none to show.
    case thinking
    case textDelta(String)
    /// A turn is not one piece of writing: the model says something, reaches
    /// for a tool, says something else, and each of those is its own content
    /// block. The deltas carry no hint of where one ends, so joining them gave
    /// `…/grill-with-docs เองได้เลยนะNo existing note on this.` — two thoughts
    /// with not even a space between them, because there was never a character
    /// there to begin with. This is that missing character.
    case textBlockBegan
    /// The session we tried to continue is gone, and this turn is starting a
    /// fresh one instead.
    ///
    /// Emitted rather than swallowed because of what it looks like from the
    /// outside: reopening a conversation from history puts the whole thread
    /// back on screen, so if the model's memory of it has expired, every
    /// following answer is written by someone who cannot see what is plainly
    /// visible to the person reading. Silently starting over is the one
    /// outcome that is indistinguishable from the app having broken.
    case sessionLost
    /// The turn finished. `stopReason == "refusal"` means the model declined.
    case completed(stopReason: Option<String>, usage: Option<ChatUsage>)
}

public enum ChatError: Error, Equatable, Sendable, LocalizedError {
    case http(status: Int, message: String)
    case network(String)
    case claudeCodeNotFound
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
