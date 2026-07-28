import FunctionalCore
import Foundation
import os

/// Drives the user's own Claude Code CLI and streams its output.
///
/// This is the "mask" model: the app never authenticates to Anthropic itself.
/// It launches the `claude` binary the user already installed and signed in to,
/// so the work runs on their account and their subscription. That also means
/// the app inherits Claude Code's real capabilities — file editing, shell, web
/// search, subagents, skills, MCP — instead of the small tool set we could
/// implement ourselves.
///
/// Deliberate choices:
/// - `ANTHROPIC_API_KEY` is stripped from the child environment. If the user
///   happens to have one exported, we must not silently spend their API credit
///   when they asked for the Claude Code path.
/// - `--bare` is never passed. It is the documented recommendation for scripted
///   calls, but it skips OAuth and keychain reads, which is exactly the
///   authentication we depend on.
/// - Conversation history lives in Claude Code's own session, resumed by ID.
///   Only the newest user turn is sent; re-sending our transcript would
///   duplicate what the session already holds.
public final class ClaudeCodeProvider: ChatProvider, @unchecked Sendable {
    /// Where and how a turn may run. Set by the orchestration layer before a
    /// turn; the permission story is a launch-time allowlist because the CLI
    /// denies un-granted tools outright rather than asking mid-turn.
    public struct Configuration: Equatable, Sendable {
        /// Working directory for the CLI — the containment boundary for this
        /// session. Nil means the process default, which we never want in
        /// production; the orchestrator sets a registered project path.
        public var workingDirectory: URL?
        /// Other folders the user has approved. Claude Code can read these too,
        /// so a question spanning several projects can be answered without
        /// making the user switch between them.
        public var additionalDirectories: [URL]
        /// Tools pre-approved for this turn, in Claude Code permission-rule
        /// syntax (e.g. `Read`, `Bash(git status *)`). Anything outside this
        /// list is refused by the CLI and reported back to the user.
        public var allowedTools: [String]
        public var permissionMode: String
        /// Whether to connect Claude Code to the user's Chrome, giving it the
        /// browser tools described in `BrowserTools`.
        ///
        /// Off unless the user turns it on. The connection reaches every site
        /// they are signed into, and Claude Code's own documentation warns that
        /// always-loaded browser tools cost context on every turn — neither is
        /// something to hand out by default.
        public var browserEnabled: Bool

        public init(
            workingDirectory: URL? = nil,
            additionalDirectories: [URL] = [],
            allowedTools: [String] = ClaudeCodeProvider.readOnlyTools,
            permissionMode: String = "manual",
            browserEnabled: Bool = false
        ) {
            self.workingDirectory = workingDirectory
            self.additionalDirectories = additionalDirectories
            self.allowedTools = allowedTools
            self.permissionMode = permissionMode
            self.browserEnabled = browserEnabled
        }
    }

    /// A conservative default: inspect and search, never modify. `Bash` is
    /// admitted only for read-only git subcommands, matching what the Secretary
    /// already offered before this pivot.
    public static let readOnlyTools = [
        "Read", "Glob", "Grep", "WebSearch", "WebFetch",
        "Bash(git status *)", "Bash(git diff *)", "Bash(git log *)", "Bash(git branch *)"
    ]

    private let installation: ClaudeCodeInstallation
    private let logger = Logger(subsystem: "com.aisecretary.app", category: "ClaudeCodeProvider")

    private let stateLock = NSLock()
    private var _configuration: Configuration
    private var _sessionID: String?
    /// Model id reported by the last session's init event.
    private var _reportedModel: String?
    /// tool_use id -> (name, input), so a refusal (which carries only the id)
    /// can be reported with what it was trying to do.
    private var _pendingToolUses: [String: (name: String, input: [String: Any])] = [:]

    public init(installation: ClaudeCodeInstallation, configuration: Configuration = Configuration()) {
        self.installation = installation
        self._configuration = configuration
    }

    public var configuration: Configuration {
        get { stateLock.withLock { _configuration } }
        set { stateLock.withLock { _configuration = newValue } }
    }

    /// Claude Code's session for this conversation, once one has started.
    public var sessionID: String? {
        stateLock.withLock { _sessionID }
    }

    /// The model the most recent session actually ran on, whether or not we
    /// asked for one.
    public var reportedModel: String? {
        stateLock.withLock { _reportedModel }
    }

    /// Forgets the session so the next turn starts a fresh one.
    public func resetSession() {
        stateLock.withLock { _sessionID = nil }
    }

    public func stream(
        messages: [ChatMessage],
        model: Option<ChatModel>,
        effort: Option<Effort>,
        maxTokens: Int,
        system: Option<String>
    ) -> ChatStream {
        let prompt = messages.last(where: { $0.role == .user })?.content ?? ""
        let configuration = self.configuration
        let resume = self.sessionID

        return AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return continuation.finish() }
                // The model is working from the moment the process starts; no
                // text arrives until it has decided what to do.
                continuation.yield(.right(.thinking))

                do {
                    let outcome = try await self.runTurn(
                        prompt: prompt, model: model, effort: effort, system: system,
                        resume: resume, configuration: configuration,
                        continuation: continuation
                    )
                    // The session we tried to resume is gone — a different
                    // directory, or one that has since been cleaned up. Starting
                    // over loses the earlier context, but that beats showing the
                    // user an internal error they can do nothing about.
                    if outcome == .staleSession {
                        self.resetSession()
                        _ = try await self.runTurn(
                            prompt: prompt, model: model, effort: effort, system: system,
                            resume: nil, configuration: configuration,
                            continuation: continuation
                        )
                    }
                } catch is CancellationError {
                    // Nothing to report: the caller asked us to stop.
                } catch {
                    continuation.yield(.left(asChatError(error, otherwise: ChatError.claudeCodeFailed)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum TurnOutcome: Equatable {
        case finished
        /// `--resume` named a session Claude Code doesn't have.
        case staleSession
    }

    private func runTurn(
        prompt: String,
        model: Option<ChatModel>,
        effort: Option<Effort>,
        system: Option<String>,
        resume: String?,
        configuration: Configuration,
        continuation: ChatStream.Continuation
    ) async throws -> TurnOutcome {
        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = Self.arguments(
            prompt: prompt, model: model, effort: effort, system: system,
            resume: resume, configuration: configuration
        )
        process.currentDirectoryURL = configuration.workingDirectory
        process.environment = Self.childEnvironment(for: installation)

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ChatError.claudeCodeFailed(error.localizedDescription)
        }

        logger.info("Claude Code turn started (resume=\(resume != nil, privacy: .public))")

        var emittedText = false
        do {
            for try await line in output.fileHandleForReading.bytes.lines {
                try Task.checkCancellation()
                for event in handle(line: line) {
                    if case .textDelta = event { emittedText = true }
                    continuation.yield(.right(event))
                }
            }
        } catch {
            process.terminate()
            throw error
        }

        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return .finished }

        let detail = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Only worth retrying if nothing reached the user yet — a mid-turn
        // failure would otherwise replay the answer from the top.
        if resume != nil, !emittedText, Self.isMissingSession(detail) {
            logger.info("Resumed session was gone; starting a fresh one")
            return .staleSession
        }

        throw ChatError.claudeCodeFailed(
            detail.isEmpty
                ? "exited with code \(process.terminationStatus)"
                : String(detail.suffix(400))
        )
    }

    static func isMissingSession(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("No conversation found")
    }

    // MARK: - Refusals

    private static func contentBlocks(of object: [String: Any]) -> [[String: Any]] {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else { return [] }
        return content
    }

    /// Distinguishes "you may not" from an ordinary tool failure such as a
    /// missing file. Only the former is worth offering to widen.
    static func isPermissionRefusal(_ message: String) -> Bool {
        let phrases = [
            "haven't granted",
            "requires approval",
            "requested permissions"
        ]
        return phrases.contains { message.localizedCaseInsensitiveContains($0) }
    }

    /// A short "what it's doing" line: the tool plus the thing it names.
    static func activityDetail(tool name: String, input: [String: Any]) -> String {
        let argument = (input["query"] as? String)
            ?? (input["command"] as? String)
            ?? (input["pattern"] as? String)
            ?? (input["url"] as? String)
            ?? (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? (input["path"] as? String)
            ?? (input["prompt"] as? String)
        guard let argument, !argument.isEmpty else { return name }
        let trimmed = argument.count > 60 ? String(argument.prefix(60)) + "…" : argument
        return "\(name): \(trimmed)"
    }

    /// Turns a refused call into something a human can decide on, plus the rule
    /// that would allow it.
    ///
    /// Bash is narrowed to the command that was actually attempted — approving
    /// one `npm test` must not hand over the whole shell.
    static func describe(tool name: String, input: [String: Any]) -> DeniedTool {
        if name == "Bash", let command = input["command"] as? String {
            let head = command.split(separator: " ").prefix(2).joined(separator: " ")
            return DeniedTool(name: name, target: .some(command), rule: "Bash(\(head) *)")
        }
        let target = Option.fromOptional(
            (input["file_path"] as? String)
                ?? (input["path"] as? String)
                ?? (input["url"] as? String)
        )
        return DeniedTool(name: name, target: target, rule: name)
    }

    // MARK: - Wire format

    /// Maps one line of `--output-format stream-json` onto our UI-agnostic
    /// events. Parsed loosely with `JSONSerialization` rather than `Codable`:
    /// the stream carries many event shapes we don't care about, and new ones
    /// appear between Claude Code releases — an unknown line must be skipped,
    /// never treated as a decoding failure.
    func handle(line: String) -> [ChatStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return [] }

        switch type {
        case "system":
            if object["subtype"] as? String == "init" {
                stateLock.withLock {
                    if let id = object["session_id"] as? String { _sessionID = id }
                    // Authoritative: what the session actually resolved to,
                    // whichever way the model was (or wasn't) specified.
                    if let model = object["model"] as? String { _reportedModel = model }
                }
            }
            return []

        case "assistant":
            // Remember what each tool call was for; the refusal that may follow
            // carries only the id.
            var events: [ChatStreamEvent] = []
            for block in Self.contentBlocks(of: object) where block["type"] as? String == "tool_use" {
                guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                let input = block["input"] as? [String: Any] ?? [:]
                stateLock.withLock { _pendingToolUses[id] = (name, input) }
                events.append(.activity(AgentActivity(kind: .tool, detail: Self.activityDetail(tool: name, input: input))))
            }
            return events

        case "user":
            var denied: [ChatStreamEvent] = []
            for block in Self.contentBlocks(of: object)
            where block["type"] as? String == "tool_result" && block["is_error"] as? Bool == true {
                guard let id = block["tool_use_id"] as? String,
                      Self.isPermissionRefusal(String(describing: block["content"] ?? ""))
                else { continue }
                let call = stateLock.withLock { _pendingToolUses.removeValue(forKey: id) }
                guard let call else { continue }
                denied.append(.toolDenied(Self.describe(tool: call.name, input: call.input)))
            }
            return denied

        case "stream_event":
            // A thinking block opening is the only signal that reasoning is
            // happening; its deltas carry no text to show.
            if let event = object["event"] as? [String: Any],
               event["type"] as? String == "content_block_start",
               let block = event["content_block"] as? [String: Any],
               block["type"] as? String == "thinking" {
                return [.activity(AgentActivity(kind: .thinking, detail: "Thinking"))]
            }
            guard let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return [] }
            return [.textDelta(text)]

        case "result":
            let usage = Option.fromOptional(object["usage"] as? [String: Any]).map {
                ChatUsage(
                    inputTokens: $0["input_tokens"] as? Int ?? 0,
                    outputTokens: $0["output_tokens"] as? Int ?? 0
                )
            }^
            return [
                .completed(
                    stopReason: Option.fromOptional(object["stop_reason"] as? String),
                    usage: usage
                )
            ]

        default:
            return []
        }
    }

    // MARK: - Launch

    static func arguments(
        prompt: String,
        model: Option<ChatModel>,
        effort: Option<Effort>,
        system: Option<String>,
        resume: String?,
        configuration: Configuration
    ) -> [String] {
        var arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", configuration.permissionMode
        ]
        // Verified against Claude Code 2.1.220: the flag connects in this
        // non-interactive shape too. The init event reports the
        // `claude-in-chrome` server as connected and its tools become
        // available, with none of the first-run dialogs the interactive CLI
        // shows — those would have hung a `-p` run with no terminal to answer.
        if configuration.browserEnabled { arguments += ["--chrome"] }
        // Only override what the user actually chose. Claude Code already has
        // their model and effort configured; forcing ours would hand them a
        // different assistant than the one they set up in the terminal.
        arguments += model.fold({ [] }, { ["--model", $0.id] })
        arguments += effort.fold({ [] }, { ["--effort", $0.rawValue] })
        if !configuration.allowedTools.isEmpty {
            arguments += ["--allowedTools", configuration.allowedTools.joined(separator: ",")]
        }
        for directory in configuration.additionalDirectories {
            arguments += ["--add-dir", directory.path]
        }
        if let resume { arguments += ["--resume", resume] }
        arguments += system.filter { !$0.isEmpty }^
            .fold({ [] }, { ["--append-system-prompt", $0] })
        return arguments
    }

    /// A deliberately small environment, with one important exception.
    ///
    /// `HOME` is required — that is where the user's Claude Code credentials and
    /// settings live. `PATH` has to carry the user's real one, not launchd's:
    /// Claude Code launches other programs (an MCP server started with `node`,
    /// a Bash command calling a Homebrew or nvm tool), and those aren't on the
    /// bare system path a Finder-launched app inherits.
    static func childEnvironment(
        for installation: ClaudeCodeInstallation,
        loginPath: Option<String> = LoginShellPath.resolve()
    ) -> [String: String] {
        let parent = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "SHELL"] {
            if let value = parent[key] { environment[key] = value }
        }
        environment["PATH"] = LoginShellPath.merged(
            binaryDirectory: installation.executableURL.deletingLastPathComponent().path,
            loginPath: loginPath,
            inherited: Option.fromOptional(parent["PATH"])
        )
        // Never inherited: an exported key would silently bill the user's API
        // credit for a session they asked to run on their subscription.
        environment.removeValue(forKey: "ANTHROPIC_API_KEY")
        return environment
    }
}
