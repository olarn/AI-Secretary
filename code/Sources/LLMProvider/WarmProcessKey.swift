import Foundation

/// Everything about a Claude Code run that is fixed the moment the process
/// starts.
///
/// This exists because of a measurement (2026-08-13, CLI 2.1.229). Every turn
/// used to be its own `claude -p --resume <id>` process: boot, config, and the
/// whole transcript read back with a cold prompt cache. Feeding one long-lived
/// process instead — `--input-format stream-json`, one user message per line —
/// took first text from 5.47s to 1.15s at the real system prompt size. The app
/// itself was never the slow part; it spawns the CLI 0.04s after Return.
///
/// The catch is that none of the values below can be changed on a running
/// process: they are command-line flags. So a turn may reuse the process it
/// finds only if every one of them still matches, and that comparison **is**
/// the invalidation mechanism — there is no separate "mark it stale" flag that
/// could be forgotten at one of the call sites that change these.
public struct WarmProcessKey: Equatable, Sendable {
    public let workingDirectory: URL?
    public let additionalDirectories: [URL]
    public let allowedTools: [String]
    public let permissionMode: String
    public let browserEnabled: Bool
    public let model: String?
    public let effort: String?
    public let system: String?
    /// The conversation the process is serving.
    ///
    /// Not a launch flag in the same sense — a fresh process is told nothing
    /// and mints its own — but it belongs here for the same reason: asking a
    /// process that is holding conversation A to answer for conversation B is
    /// not something a flag can fix afterwards. A process that minted its own
    /// records that id here as soon as the init event names it, so the next
    /// turn recognises itself rather than restarting.
    public let session: String?

    public init(
        workingDirectory: URL?,
        additionalDirectories: [URL],
        allowedTools: [String],
        permissionMode: String,
        browserEnabled: Bool,
        model: String?,
        effort: String?,
        system: String?,
        session: String?
    ) {
        self.workingDirectory = workingDirectory
        self.additionalDirectories = additionalDirectories
        self.allowedTools = allowedTools
        self.permissionMode = permissionMode
        self.browserEnabled = browserEnabled
        self.model = model
        self.effort = effort
        self.system = system
        self.session = session
    }

    public func canBeServed(by running: WarmProcessKey) -> Bool {
        self == running
    }
}

/// One user message, in the shape `--input-format stream-json` reads.
///
/// Hand-built rather than `JSONEncoder`ed over a model type: it is three nested
/// objects with one string in them, and the wire shape is the CLI's, not ours —
/// a Codable type here would invite someone to add a field to it.
public func warmTurnInputLine(prompt: String) -> String? {
    let payload: [String: Any] = [
        "type": "user",
        "message": ["role": "user", "content": [["type": "text", "text": prompt]]],
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
    // One line, and the newline is what tells the CLI the message is complete.
    return String(decoding: data, as: UTF8.self) + "\n"
}
