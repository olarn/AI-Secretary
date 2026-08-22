import FunctionalCore
import Foundation

public struct OpenCodeReading: Equatable, Sendable {
    public let events: [ChatStreamEvent]
    public let textByPart: [String: String]
    public let sessionID: Option<String>
    public let usage: Option<ChatUsage>

    public init(
        events: [ChatStreamEvent],
        textByPart: [String: String],
        sessionID: Option<String> = .none(),
        usage: Option<ChatUsage> = .none()
    ) {
        self.events = events
        self.textByPart = textByPart
        self.sessionID = sessionID
        self.usage = usage
    }
}

public func openCodeReading(line: String, textByPart: [String: String] = [:]) -> OpenCodeReading {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return OpenCodeReading(events: [], textByPart: textByPart)
    }
    let session = Option.fromOptional(object["sessionID"] as? String)
    let part = object["part"] as? [String: Any] ?? [:]

    switch object["type"] as? String {
    case "step_start":
        return OpenCodeReading(events: [.textBlockBegan], textByPart: textByPart, sessionID: session)
    case "text":
        return openCodeTextReading(part: part, textByPart: textByPart, session: session)
    case "tool_use":
        return OpenCodeReading(
            events: [.activity(AgentActivity(kind: .tool, detail: openCodeToolLabel(part)))],
            textByPart: textByPart,
            sessionID: session
        )
    case "step_finish":
        return OpenCodeReading(
            events: [],
            textByPart: textByPart,
            sessionID: session,
            usage: openCodeUsage(part)
        )
    default:
        return OpenCodeReading(events: [], textByPart: textByPart, sessionID: session)
    }
}

private func openCodeTextReading(
    part: [String: Any],
    textByPart: [String: String],
    session: Option<String>
) -> OpenCodeReading {
    guard let id = part["id"] as? String, let whole = part["text"] as? String else {
        return OpenCodeReading(events: [], textByPart: textByPart, sessionID: session)
    }
    let already = textByPart[id] ?? ""
    let partWasExtendedRatherThanRewritten = whole.hasPrefix(already)
    let tail = partWasExtendedRatherThanRewritten ? String(whole.dropFirst(already.count)) : whole
    var updated = textByPart
    updated[id] = whole
    return OpenCodeReading(
        events: tail.isEmpty ? [] : [.textDelta(tail)],
        textByPart: updated,
        sessionID: session
    )
}

func openCodeToolLabel(_ part: [String: Any]) -> String {
    let name = part["tool"] as? String ?? "tool"
    let state = part["state"] as? [String: Any] ?? [:]
    return Option.fromOptional(state["title"] as? String)
        .map { $0.trimmingCharacters(in: .whitespaces) }^
        .filter { !$0.isEmpty }^
        .map { "\(name): \($0)" }^
        .getOrElse(name)
}

func openCodeUsage(_ part: [String: Any]) -> Option<ChatUsage> {
    guard let tokens = part["tokens"] as? [String: Any] else { return .none() }
    let cache = tokens["cache"] as? [String: Any] ?? [:]
    return .some(
        ChatUsage(
            inputTokens: tokens["input"] as? Int ?? 0,
            outputTokens: tokens["output"] as? Int ?? 0,
            cacheWriteTokens: cache["write"] as? Int ?? 0,
            cacheReadTokens: cache["read"] as? Int ?? 0,
            costUSD: part["cost"] as? Double ?? 0
        )
    )
}

public func openCodePrompt(system: Option<String>, message: String) -> String {
    system
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }^
        .filter { !$0.isEmpty }^
        .map { "\($0)\n\n---\n\n\(message)" }^
        .getOrElse(message)
}

public func openCodeArguments(
    model: Option<ChatModel>,
    variant: Option<String>,
    session: Option<String>,
    workingDirectory: URL?,
    prompt: String
) -> [String] {
    let base = ["run", "--format", "json"]
    let dir = workingDirectory.map { ["--dir", $0.path] } ?? []
    let modelFlag = model.map { ["--model", $0.id] }^.getOrElse([])
    let variantFlag = variant.map { ["--variant", $0] }^.getOrElse([])
    let resume = session.map { ["--session", $0] }^.getOrElse([])
    let messageLastAndBehindADoubleDash = ["--", prompt]
    return base + dir + modelFlag + variantFlag + resume + messageLastAndBehindADoubleDash
}
