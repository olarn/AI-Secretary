import FunctionalCore
import Foundation

public struct ClaudeCodeDefaults: Equatable, Sendable {
    public let model: Option<ChatModel>
    public let effort: Option<Effort>

    public init(model: Option<ChatModel> = .none(), effort: Option<Effort> = .none()) {
        self.model = model
        self.effort = effort
    }

    public static let unknown = ClaudeCodeDefaults()

    static let claudeCodesOwnKeyForEffort = "effortLevel"

    static var settingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }

    public static func read(from url: URL? = nil) -> ClaudeCodeDefaults {
        guard let data = try? Data(contentsOf: url ?? settingsURL) else { return .unknown }
        return parse(data)
    }

    static func parse(_ data: Data) -> ClaudeCodeDefaults {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }
        return ClaudeCodeDefaults(
            model: Option.fromOptional(object["model"] as? String).flatMap(ChatModel.named)^,
            effort: Option.fromOptional(object[Self.claudeCodesOwnKeyForEffort] as? String).flatMap(Effort.named)^
        )
    }
}
