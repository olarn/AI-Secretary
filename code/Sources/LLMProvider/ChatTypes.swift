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

    static let shortNamesClaudeCodeItselfAccepts: [String: ChatModel] = [
        "opus": opus5,
        "sonnet": sonnet5,
        "fable": fable5,
        "haiku": haiku45
    ]

    static let wordsThatMeanDoNotChooseForMe: Set<String> = ["default", "auto", "inherit"]

    public static func named(_ raw: String) -> Option<ChatModel> {
        let needle = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return Option.fromOptional(shortNamesClaudeCodeItselfAccepts[needle])
            .orElse(Option.fromOptional(known.first { $0.id.lowercased() == needle }))
    }

    public static func meansInherit(_ raw: String) -> Bool {
        wordsThatMeanDoNotChooseForMe.contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

public enum Effort: String, CaseIterable, Sendable {
    case low, medium, high, xhigh, max

    public static func named(_ raw: String) -> Option<Effort> {
        Option.fromOptional(Effort(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()))
    }
}

public struct ChatUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheWriteTokens: Int
    public let cacheReadTokens: Int
    public let costUSD: Double
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

public struct DeniedTool: Equatable, Sendable {
    public let name: String
    public let target: Option<String>
    public let rules: [String]
    public let directory: Option<String>

    public init(
        name: String,
        target: Option<String>,
        rules: [String],
        directory: Option<String> = .none()
    ) {
        self.name = name
        self.target = target
        self.rules = rules
        self.directory = directory
    }

    public var summary: String {
        target.filter { !$0.isEmpty }^
            .fold({ self.name }, { "\(self.name): \($0)" })
    }
}

public enum ActivityOrigin: Equatable, Sendable {
    case main
    case subagent(String)
}

public struct AgentActivity: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case thinking, tool }

    public let id = UUID()
    public let kind: Kind
    public let detail: String
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

public struct SubagentTask: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let detail: String
    public let lastTool: Option<String>

    public init(id: String, kind: String, detail: String, lastTool: Option<String> = .none()) {
        self.id = id
        self.kind = kind
        self.detail = detail
        self.lastTool = lastTool
    }
}

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

public enum ChatStreamEvent: Equatable, Sendable {
    case toolDenied(DeniedTool)
    case activity(AgentActivity)
    case subagentStarted(SubagentTask)
    case subagentProgress(SubagentTask)
    case subagentFinished(SubagentOutcome)
    case thinking
    case textDelta(String)
    case textBlockBegan
    case sessionLost
    case completed(stopReason: Option<String>, usage: Option<ChatUsage>)
}

public enum ChatError: Error, Equatable, Sendable, LocalizedError {
    case http(status: Int, message: String)
    case network(String)
    case claudeCodeNotFound
    case claudeCodeFailed(String)
    case vendorFailed(vendor: String, detail: String)

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
        case .vendorFailed(let vendor, let detail):
            return "\(vendor) couldn't finish: \(detail)"
        case .claudeCodeFailed(let detail):
            return ClaudeCodeFailure.classify(detail).message(detail: detail)
        }
    }
}

public typealias ChatStream = AsyncStream<Either<ChatError, ChatStreamEvent>>
