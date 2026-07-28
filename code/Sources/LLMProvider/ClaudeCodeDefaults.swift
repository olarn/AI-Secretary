import FunctionalCore
import Foundation

/// What the user's own Claude Code is configured to use.
///
/// The app deliberately doesn't pass `--model`/`--effort` unless the user picks
/// something here, which leaves the settings panel with nothing concrete to
/// show. Reading their configuration lets it name the real model instead of
/// "your default" — the same answer they'd get in the terminal.
///
/// Best effort by design: a missing or unreadable file just means we don't know
/// yet, and the value reported by a live session takes precedence anyway.
public struct ClaudeCodeDefaults: Equatable, Sendable {
    public let model: Option<ChatModel>
    public let effort: Option<Effort>

    public init(model: Option<ChatModel> = .none(), effort: Option<Effort> = .none()) {
        self.model = model
        self.effort = effort
    }

    public static let unknown = ClaudeCodeDefaults()

    static var settingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }

    public static func read(from url: URL? = nil) -> ClaudeCodeDefaults {
        guard let data = try? Data(contentsOf: url ?? settingsURL) else { return .unknown }
        return parse(data)
    }

    /// `model` may be an alias (`opus`) or a full id; `effortLevel` is Claude
    /// Code's own key name for the effort setting.
    static func parse(_ data: Data) -> ClaudeCodeDefaults {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }
        return ClaudeCodeDefaults(
            model: Option.fromOptional(object["model"] as? String).flatMap(ChatModel.named)^,
            effort: Option.fromOptional(object["effortLevel"] as? String).flatMap(Effort.named)^
        )
    }
}
