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
public final class ClaudeCodeProvider: ChatProvider, SkillInstalling, @unchecked Sendable {
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

    /// Tools the character must never have, whatever else is allowed.
    ///
    /// `--allowedTools` does not do this job: it is an *auto-approve* list, so
    /// everything left off it still exists and merely asks. These have to be
    /// denied outright.
    ///
    /// Claude Code can message other Claude Code sessions, and the moment a
    /// character was told other characters existed she reached for exactly
    /// that. Driven on 2026-08-14: asked to get something from Pikachu, Ditto
    /// called `ListAgents`, went looking with `ToolSearch`, called
    /// `SendMessage`, and then told the person **"ส่งสำเร็จแล้วครับ! ข้อความไปถึง
    /// Pikachu (session my-mcp-server-80)"** — a confident report of something
    /// that never happened, addressed to a Claude Code session that has nothing
    /// to do with the character of that name. Pikachu, of course, said nothing.
    ///
    /// The tools are real and they work; what they do not do is reach the
    /// characters on this desktop, and no wording in a prompt makes a tool that
    /// is right there stop looking like the answer. The relay is the app's job,
    /// and this is what keeps it the app's job.
    public static let deniedTools = ["SendMessage", "ListAgents"]

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
    /// The process kept alive between turns. Nil while a turn is using it —
    /// see `takeWarm` — and nil when the last one was ended.
    private var _warm: WarmProcess?

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

    public func resetSession() {
        stateLock.withLock { _sessionID = nil }
    }

    /// Points the next turn at an existing session, so a conversation reopened
    /// from history continues rather than restarts.
    ///
    /// Whether that session still exists is not knowable from here — it lives
    /// in Claude Code's own storage and can be cleaned up at any time. A dead
    /// one comes back as `.staleSession` on the next turn and is handled there.
    public func adopt(session id: String?) {
        stateLock.withLock { _sessionID = id }
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
                        // Only worth saying when we asked for a specific
                        // thread. A session that expired between two turns of
                        // the conversation you are looking at is the same
                        // event, and just as worth knowing.
                        if resume != nil { continuation.yield(.right(.sessionLost)) }
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
        let key = WarmProcessKey(
            workingDirectory: configuration.workingDirectory,
            additionalDirectories: configuration.additionalDirectories,
            allowedTools: configuration.allowedTools,
            permissionMode: configuration.permissionMode,
            browserEnabled: configuration.browserEnabled,
            model: model.toOptional()?.id,
            effort: effort.toOptional()?.rawValue,
            system: system.toOptional(),
            session: resume
        )

        // The process from the last turn, if it is still the right process and
        // still alive. Comparing the key is the whole invalidation story: every
        // way the configuration can change goes through `configuration` or
        // `sessionID`, and both are read into the key here.
        let reused = takeWarm(matching: key)
        let warm: WarmProcess
        if let reused {
            warm = reused
        } else {
            warm = try startWarm(
                key: key, model: model, effort: effort,
                system: system, resume: resume, configuration: configuration
            )
        }

        guard let line = warmTurnInputLine(prompt: prompt) else {
            throw ChatError.claudeCodeFailed("could not encode the message")
        }
        do {
            try warm.send(line)
        } catch {
            // A process that died quietly between turns. One retry on a fresh
            // one, because from the person's side nothing has happened yet.
            guard reused != nil else {
                throw ChatError.claudeCodeFailed(error.localizedDescription)
            }
            logger.info("Warm Claude Code process was gone; starting a new one")
            return try await runTurn(
                prompt: prompt, model: model, effort: effort, system: system,
                resume: resume, configuration: configuration, continuation: continuation
            )
        }

        logger.info("Claude Code turn started (warm=\(reused != nil, privacy: .public))")
        return try await readTurn(from: warm, wasReused: reused != nil, continuation: continuation)
    }

    /// Stops at the result line, which is what keeps two turns apart down one
    /// process: read past it and the next turn's events land on the last turn's
    /// bubble.
    private func readTurn(
        from warm: WarmProcess,
        wasReused: Bool,
        continuation: ChatStream.Continuation
    ) async throws -> TurnOutcome {
        var emittedText = false
        do {
            while let line = try await warm.nextLine() {
                try Task.checkCancellation()
                let finished = Self.isTurnResult(line)
                for event in handle(line: line) {
                    if case .textDelta = event { emittedText = true }
                    continuation.yield(.right(event))
                }
                if finished {
                    // Whatever session it is serving, it is serving it now —
                    // including one it minted itself, which the next turn has
                    // to recognise or it would start over.
                    keepWarm(warm.adopting(session: sessionID))
                    return .finished
                }
            }
        } catch {
            // Cancellation included: a half-answered process cannot be handed
            // to the next turn, so it goes rather than being kept.
            warm.terminate()
            throw error
        }

        // Out of lines with no result: the process ended mid-turn.
        warm.terminate()
        let detail = warm.errorText()

        // Only worth retrying if nothing reached the user yet — a mid-turn
        // failure would otherwise replay the answer from the top.
        if warm.key.session != nil, !emittedText, Self.isMissingSession(detail) {
            logger.info("Resumed session was gone; starting a fresh one")
            return .staleSession
        }

        throw ChatError.claudeCodeFailed(
            detail.isEmpty ? "Claude Code stopped without answering" : String(detail.suffix(400))
        )
    }

    /// The line that ends a turn. `--output-format stream-json` sends exactly
    /// one of these per turn, after everything it had to say.
    static func isTurnResult(_ line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object["type"] as? String == "result"
    }

    private func startWarm(
        key: WarmProcessKey,
        model: Option<ChatModel>,
        effort: Option<Effort>,
        system: Option<String>,
        resume: String?,
        configuration: Configuration
    ) throws -> WarmProcess {
        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = Self.launchArguments(
            model: model, effort: effort, system: system,
            resume: resume, configuration: configuration
        )
        process.currentDirectoryURL = configuration.workingDirectory
        process.environment = Self.childEnvironment(for: installation)

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw ChatError.claudeCodeFailed(error.localizedDescription)
        }
        return WarmProcess(process: process, input: input, output: output, errors: errors, key: key)
    }

    /// Taken out rather than borrowed: a turn owns it until it hands it back,
    /// so a second turn can never read the same stream.
    private func takeWarm(matching key: WarmProcessKey) -> WarmProcess? {
        stateLock.withLock {
            guard let warm = _warm else { return nil }
            guard key.canBeServed(by: warm.key), warm.isRunning else {
                warm.terminate()
                _warm = nil
                return nil
            }
            _warm = nil
            return warm
        }
    }

    private func keepWarm(_ warm: WarmProcess) {
        stateLock.withLock {
            _warm?.terminate()
            _warm = warm
        }
    }

    /// Ends the kept process. The next turn starts a new one and resumes the
    /// session by id, so nothing is lost but the warmth.
    public func stopWarmProcess() {
        stateLock.withLock {
            _warm?.terminate()
            _warm = nil
        }
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
    static func isPermissionRefusal(_ message: String, tool: String = "") -> Bool {
        var phrases = [
            "haven't granted",
            "requires approval",
            // Plural, and not a substring of the singular: a command with more
            // than one operation is refused with "The following parts require
            // approval: …". Without this line that refusal read as an ordinary
            // failure, so nothing was offered and the wall had no door — every
            // `cd … && python3 …` the owner tried landed here.
            "require approval",
            "requested permissions"
        ]
        // The browser tools word their refusal differently — "Claude in Chrome
        // requires permission" — and matched none of the three above, so a
        // blocked scroll or click was never recognised as blocked: the app
        // reported it as prose and never offered to allow it. Verified in the
        // app that granting the rule is what unblocks it, so this belongs on
        // the same try-refuse-ask-retry path as everything else.
        //
        // Only for browser tools. "requires permission" is broad enough that an
        // unrelated tool failing for its own reasons would otherwise be read as
        // a refusal, and the user would be offered a grant for something that
        // was never blocked.
        if BrowserTools.isBrowserTool(tool) {
            phrases.append("requires permission")
        }
        return phrases.contains { message.localizedCaseInsensitiveContains($0) }
    }

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
    /// Bash is narrowed to the commands that were actually attempted —
    /// approving one `npm test` must not hand over the whole shell — and it is
    /// commands, plural: see `bashPermissionRules` for why one rule for the
    /// whole line left the person approving something that then failed anyway.
    static func describe(tool name: String, input: [String: Any]) -> DeniedTool {
        if name == "Bash", let command = input["command"] as? String {
            return DeniedTool(
                name: name,
                target: .some(command),
                rules: bashPermissionRules(for: command)
            )
        }
        let target = Option.fromOptional(
            (input["file_path"] as? String)
                ?? (input["path"] as? String)
                ?? (input["url"] as? String)
        )
        return DeniedTool(name: name, target: target, rules: [name])
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

        // One line of the CLI's JSON is one kind of thing, and each kind is its
        // own reader below. As one body it was a hundred lines whose arms had
        // nothing to do with each other but had to be read together anyway.
        switch type {
        case "system": return adoptSession(from: object)
        case "assistant": return toolCalls(in: object)
        case "user": return refusals(in: object)
        case "stream_event": return streamEvents(in: object)
        case "result": return [completion(from: object)]
        default: return []
        }
    }

    /// The init line is the only place the session id and the model actually
    /// resolved to are reported. Nothing to show for it — it changes what the
    /// next turn is sent with, not what is on screen.
    private func adoptSession(from object: [String: Any]) -> [ChatStreamEvent] {
        guard object["subtype"] as? String == "init" else { return [] }
        stateLock.withLock {
            if let id = object["session_id"] as? String { _sessionID = id }
            // Authoritative: what the session actually resolved to, whichever
            // way the model was (or wasn't) specified.
            if let model = object["model"] as? String { _reportedModel = model }
        }
        return []
    }

    /// Remembers what each tool call was for; the refusal that may follow
    /// carries only the id.
    private func toolCalls(in object: [String: Any]) -> [ChatStreamEvent] {
        Self.contentBlocks(of: object)
            .filter { $0["type"] as? String == "tool_use" }
            .compactMap { block in
                guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
                let input = block["input"] as? [String: Any] ?? [:]
                stateLock.withLock { _pendingToolUses[id] = (name, input) }
                return .activity(AgentActivity(kind: .tool, detail: Self.activityDetail(tool: name, input: input)))
            }
    }

    private func refusals(in object: [String: Any]) -> [ChatStreamEvent] {
        Self.contentBlocks(of: object)
            .filter { $0["type"] as? String == "tool_result" && $0["is_error"] as? Bool == true }
            .compactMap { block in
                guard let id = block["tool_use_id"] as? String,
                      let call = stateLock.withLock({ _pendingToolUses[id] })
                else { return nil }
                // Which tool it was decides which refusals count, so the call is
                // looked up first and only dropped once it's been judged.
                guard Self.isPermissionRefusal(
                    String(describing: block["content"] ?? ""),
                    tool: call.name
                ) else { return nil }
                stateLock.withLock { _pendingToolUses.removeValue(forKey: id) }
                return .toolDenied(Self.describe(tool: call.name, input: call.input))
            }
    }

    private func streamEvents(in object: [String: Any]) -> [ChatStreamEvent] {
        guard let event = object["event"] as? [String: Any] else { return [] }

        // A thinking block opening is the only signal that reasoning is
        // happening; its deltas carry no text to show.
        if event["type"] as? String == "content_block_start",
           let block = event["content_block"] as? [String: Any] {
            switch block["type"] as? String {
            case "thinking":
                return [.activity(AgentActivity(kind: .thinking, detail: "Thinking"))]
            case "text":
                // Where one thing the model said ends and the next begins. The
                // deltas alone can't say — they are just characters, and the
                // last of one block butts against the first of the next.
                return [.textBlockBegan]
            default:
                return []
            }
        }

        guard event["type"] as? String == "content_block_delta",
              let delta = event["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta",
              let text = delta["text"] as? String
        else { return [] }
        return [.textDelta(text)]
    }

    private func completion(from object: [String: Any]) -> ChatStreamEvent {
        // Cost and the context window sit beside `usage`, not inside it.
        let cost = object["total_cost_usd"] as? Double ?? 0
        let window = Self.contextWindow(of: object)
        let usage = Option.fromOptional(object["usage"] as? [String: Any]).map {
            ChatUsage(
                inputTokens: $0["input_tokens"] as? Int ?? 0,
                outputTokens: $0["output_tokens"] as? Int ?? 0,
                // Left out until now, which made the reported figure useless on
                // any real turn: these two are almost all of the traffic.
                cacheWriteTokens: $0["cache_creation_input_tokens"] as? Int ?? 0,
                cacheReadTokens: $0["cache_read_input_tokens"] as? Int ?? 0,
                costUSD: cost,
                contextWindow: window
            )
        }^
        return .completed(
            stopReason: Option.fromOptional(object["stop_reason"] as? String),
            usage: usage
        )
    }

    /// The context window, dug out of `modelUsage`, which is keyed by model id.
    ///
    /// Only one model answers a turn, so the largest window present is that
    /// model's — and taking the largest means a turn that somehow lists two
    /// can't report the smaller one and make the bar look fuller than it is.
    static func contextWindow(of object: [String: Any]) -> Int? {
        guard let models = object["modelUsage"] as? [String: Any] else { return nil }
        return models.values
            .compactMap { ($0 as? [String: Any])?["contextWindow"] as? Int }
            .max()
    }

    // MARK: - Installing a skill

    /// Runs `claude plugin install` for a name a human has just approved.
    ///
    /// The name is checked again here rather than trusted from the caller. It
    /// began life in a model's reply, and the check is one comparison against a
    /// character set — cheap enough that the version which cannot be reached by
    /// forgetting a call is the one to have.
    public func installSkill(named plugin: String) async -> Either<String, String> {
        guard validSkillPluginName(plugin) else {
            return .left("“\(plugin)” isn't a plugin name I'm willing to hand to the installer.")
        }
        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = skillInstallArguments(plugin: plugin)
        process.environment = Self.childEnvironment(for: installation)

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .left(error.localizedDescription)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            // The installer's own words: it is the thing that knows the name
            // isn't in any marketplace the person has added, and that is the
            // most likely reason to be here.
            return .left(text.isEmpty ? "The installer exited \(process.terminationStatus)." : text)
        }
        return .right(text)
    }

    /// The command line for one long-lived process.
    ///
    /// Every flag here is fixed for that process's whole life — which is why
    /// `WarmProcessKey` exists and why a turn that wants any of them different
    /// gets a new process rather than a new flag.
    static func launchArguments(
        model: Option<ChatModel>,
        effort: Option<Effort>,
        system: Option<String>,
        resume: String?,
        configuration: Configuration
    ) -> [String] {
        var arguments = [
            "--output-format", "stream-json",
            // Turns arrive one JSON line at a time down stdin, so the process
            // outlives the turn. Measured worth: first text 5.47s → 1.15s.
            //
            // It also retires an old hazard rather than working around it. The
            // message used to be a command-line argument, and one beginning
            // with a dash was read as a flag — `unknown option '- A…'` — which
            // is why it had to go last, behind `--`. A JSON string on stdin is
            // not parsed as anything, so no message can be mistaken for a flag.
            "--input-format", "stream-json",
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
        arguments += ["--disallowedTools", ClaudeCodeProvider.deniedTools.joined(separator: ",")]
        for directory in configuration.additionalDirectories {
            arguments += ["--add-dir", directory.path]
        }
        if let resume { arguments += ["--resume", resume] }
        arguments += system.filter { !$0.isEmpty }^
            .fold({ [] }, { ["--append-system-prompt", $0] })
        arguments += ["-p"]
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
