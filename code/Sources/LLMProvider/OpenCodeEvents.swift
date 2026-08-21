import FunctionalCore
import Foundation

/// What one line of `opencode run --format json` means, read into the app's own
/// vocabulary.
///
/// Everything here was measured against opencode 1.18.15 on 2026-08-21 by
/// running real turns and keeping the output; none of it is inferred from
/// documentation. The shape is one JSON object per line:
///
/// ```
/// {"type":"step_start",  "timestamp":…, "sessionID":"ses_…", "part":{…}}
/// {"type":"tool_use",    …, "part":{"tool":"read","state":{"status":"completed","title":…}}}
/// {"type":"text",        …, "part":{"id":"prt_…","text":"pong"}}
/// {"type":"step_finish", …, "part":{"tokens":{…},"cost":0}}
/// ```
///
/// Pure, and threading its own carry-over rather than holding it, so a whole
/// turn can be replayed in a test from the captured lines.
public struct OpenCodeReading: Equatable, Sendable {
    public let events: [ChatStreamEvent]
    /// What has already been handed out, per part id.
    ///
    /// opencode may re-send a part as it grows; the app's `textDelta` means
    /// "append this", so re-sending a whole part would print it twice. Keeping
    /// what was emitted turns a re-send into its new tail, and an unchanged
    /// re-send into nothing at all.
    public let textByPart: [String: String]
    /// The thread opencode is keeping this turn in, for `--session` next time.
    public let sessionID: Option<String>
    /// Present on `step_finish`. A turn has one per step, so the caller keeps
    /// the last rather than the first.
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

/// Reads one line. An unreadable or unknown line is *nothing happened*, never a
/// failure — the same rule the Claude reader follows, and for the same reason:
/// a new event type in a later opencode must not break a turn that is otherwise
/// going fine.
public func openCodeReading(line: String, textByPart: [String: String] = [:]) -> OpenCodeReading {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return OpenCodeReading(events: [], textByPart: textByPart)
    }
    let session = Option.fromOptional(object["sessionID"] as? String)
    let part = object["part"] as? [String: Any] ?? [:]

    switch object["type"] as? String {
    case "step_start":
        // A turn is several steps — say something, use a tool, say something
        // else — and each step's text is its own block. Without this the last
        // word of one step and the first of the next are printed with nothing
        // between them, which is the bug `textBlockBegan` was added for.
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

/// Only the part that is new. An identical re-send yields no event at all.
private func openCodeTextReading(
    part: [String: Any],
    textByPart: [String: String],
    session: Option<String>
) -> OpenCodeReading {
    guard let id = part["id"] as? String, let whole = part["text"] as? String else {
        return OpenCodeReading(events: [], textByPart: textByPart, sessionID: session)
    }
    let already = textByPart[id] ?? ""
    // Only a genuine extension is a tail. A part that was rewritten rather than
    // extended is sent whole, because printing its tail would print a fragment
    // of a sentence that no longer starts where the reader thinks it does.
    let tail = whole.hasPrefix(already) ? String(whole.dropFirst(already.count)) : whole
    var updated = textByPart
    updated[id] = whole
    return OpenCodeReading(
        events: tail.isEmpty ? [] : [.textDelta(tail)],
        textByPart: updated,
        sessionID: session
    )
}

/// opencode writes its own human label for a tool call — `state.title` reads
/// `Users/me/project/file.swift` for a read. Preferred over the bare tool name
/// because it is the half that says *what*, which is what the activity row is
/// for; the name alone is used when there is no title yet.
func openCodeToolLabel(_ part: [String: Any]) -> String {
    let name = part["tool"] as? String ?? "tool"
    let state = part["state"] as? [String: Any] ?? [:]
    return Option.fromOptional(state["title"] as? String)
        .map { $0.trimmingCharacters(in: .whitespaces) }^
        .filter { !$0.isEmpty }^
        .map { "\(name): \($0)" }^
        .getOrElse(name)
}

/// `tokens` splits cache reads and writes the same way the app's own type does,
/// so nothing is inferred. `cost` is 0 for a local model, which is true rather
/// than unknown.
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

/// The character's standing instructions, in front of what she was just asked.
///
/// opencode has no `--append-system-prompt`. Its equivalent is `--agent`, which
/// means a file the user has to write and keep in step with a profile they edit
/// in this app — two places to change one personality. Prepending is the honest
/// alternative and it is not free: the model sees the instructions as something
/// the user said, which is weaker than a real system prompt. Said here so the
/// next person weighing `--agent` knows the trade rather than rediscovering it.
///
/// Without this the persona never arrived at all: the first turn driven through
/// opencode carried the roster preamble and the question, and nothing about who
/// she is (2026-08-21).
public func openCodePrompt(system: Option<String>, message: String) -> String {
    system
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }^
        .filter { !$0.isEmpty }^
        .map { "\($0)\n\n---\n\n\(message)" }^
        .getOrElse(message)
}

/// The argv for one turn.
///
/// Free and pure so the flags can be asserted without spawning anything — the
/// order and the `--` are load-bearing, see below.
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
    // The message goes last and behind `--`, the same rule the Claude path
    // follows: a message beginning with a dash is otherwise read as a flag, so
    // asking about a flag, or sending a bullet list, fails to send at all.
    // Nothing may be appended after this.
    return base + dir + modelFlag + variantFlag + resume + ["--", prompt]
}
