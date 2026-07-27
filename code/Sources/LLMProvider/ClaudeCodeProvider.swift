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
        /// Tools pre-approved for this turn, in Claude Code permission-rule
        /// syntax (e.g. `Read`, `Bash(git status *)`). Anything outside this
        /// list is refused by the CLI and reported back to the user.
        public var allowedTools: [String]
        public var permissionMode: String

        public init(
            workingDirectory: URL? = nil,
            allowedTools: [String] = ClaudeCodeProvider.readOnlyTools,
            permissionMode: String = "manual"
        ) {
            self.workingDirectory = workingDirectory
            self.allowedTools = allowedTools
            self.permissionMode = permissionMode
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

    /// Forgets the session so the next turn starts a fresh one.
    public func resetSession() {
        stateLock.withLock { _sessionID = nil }
    }

    public func stream(
        messages: [ChatMessage],
        model: ChatModel,
        effort: Effort,
        maxTokens: Int,
        system: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let prompt = messages.last(where: { $0.role == .user })?.content ?? ""
        let configuration = self.configuration
        let resume = self.sessionID

        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return continuation.finish() }
                // The model is working from the moment the process starts; no
                // text arrives until it has decided what to do.
                continuation.yield(.thinking)

                do {
                    let outcome = try await self.runTurn(
                        prompt: prompt, model: model, system: system,
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
                            prompt: prompt, model: model, system: system,
                            resume: nil, configuration: configuration,
                            continuation: continuation
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
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
        model: ChatModel,
        system: String?,
        resume: String?,
        configuration: Configuration,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws -> TurnOutcome {
        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = Self.arguments(
            prompt: prompt, model: model, system: system,
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
                    continuation.yield(event)
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
            if object["subtype"] as? String == "init",
               let id = object["session_id"] as? String {
                stateLock.withLock { _sessionID = id }
            }
            return []

        case "stream_event":
            guard let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return [] }
            return [.textDelta(text)]

        case "result":
            let usage = (object["usage"] as? [String: Any]).map {
                ChatUsage(
                    inputTokens: $0["input_tokens"] as? Int ?? 0,
                    outputTokens: $0["output_tokens"] as? Int ?? 0
                )
            }
            return [.completed(stopReason: object["stop_reason"] as? String, usage: usage)]

        default:
            return []
        }
    }

    // MARK: - Launch

    static func arguments(
        prompt: String,
        model: ChatModel,
        system: String?,
        resume: String?,
        configuration: Configuration
    ) -> [String] {
        var arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--model", model.id,
            "--permission-mode", configuration.permissionMode
        ]
        if !configuration.allowedTools.isEmpty {
            arguments += ["--allowedTools", configuration.allowedTools.joined(separator: ",")]
        }
        if let resume { arguments += ["--resume", resume] }
        if let system, !system.isEmpty { arguments += ["--append-system-prompt", system] }
        return arguments
    }

    /// A deliberately small environment. `HOME` is required — that is where the
    /// user's Claude Code credentials and settings live. `PATH` includes the
    /// binary's own directory so Claude Code can find tools shipped beside it.
    static func childEnvironment(for installation: ClaudeCodeInstallation) -> [String: String] {
        let parent = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "SHELL"] {
            if let value = parent[key] { environment[key] = value }
        }
        let binDirectory = installation.executableURL.deletingLastPathComponent().path
        let base = parent["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = base.contains(binDirectory) ? base : "\(binDirectory):\(base)"
        // Never inherited: an exported key would silently bill the user's API
        // credit for a session they asked to run on their subscription.
        environment.removeValue(forKey: "ANTHROPIC_API_KEY")
        return environment
    }
}
