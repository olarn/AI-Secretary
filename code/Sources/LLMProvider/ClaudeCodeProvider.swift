import FunctionalCore
import Foundation
import os

private let toolsThatWouldLetHerMessageOtherClaudeCodeSessionsInsteadOfTheCharacters = ["SendMessage", "ListAgents"]

private let phrasesClaudeCodeUsesWhenItRefusesATool = [
    "haven't granted",
    "requires approval",
    "require approval",
    "requested permissions"
]

private let phraseTheBrowserToolsUseWhichIsTooBroadForAnyOtherTool = "requires permission"

private let phraseClaudeCodeUsesWhenTheResumedSessionIsGone = "No conversation found"

public final class ClaudeCodeProvider: ChatProvider, SkillInstalling, @unchecked Sendable {
    public struct Configuration: Equatable, Sendable {
        public var workingDirectory: URL?
        public var additionalDirectories: [URL]
        public var allowedTools: [String]
        public var permissionMode: String
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

    public static let readOnlyTools = [
        "Read", "Glob", "Grep", "WebSearch", "WebFetch",
        "Bash(git status *)", "Bash(git diff *)", "Bash(git log *)", "Bash(git branch *)"
    ]

    public static let deniedTools = toolsThatWouldLetHerMessageOtherClaudeCodeSessionsInsteadOfTheCharacters

    private let installation: ClaudeCodeInstallation
    private let logger = Logger(subsystem: "com.aisecretary.app", category: "ClaudeCodeProvider")

    private let stateLock = NSLock()
    private var _configuration: Configuration
    private var _sessionID: String?
    private var _reportedModel: String?
    private var _pendingToolUses: [String: (name: String, input: [String: Any])] = [:]
    private var _warm: WarmProcess?

    public init(installation: ClaudeCodeInstallation, configuration: Configuration = Configuration()) {
        self.installation = installation
        self._configuration = configuration
    }

    public var configuration: Configuration {
        get { stateLock.withLock { _configuration } }
        set { stateLock.withLock { _configuration = newValue } }
    }

    public var sessionID: String? {
        stateLock.withLock { _sessionID }
    }

    public var reportedModel: String? {
        stateLock.withLock { _reportedModel }
    }

    public func resetSession() {
        stateLock.withLock { _sessionID = nil }
    }

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
                continuation.yield(.right(.thinking))

                do {
                    let outcome = try await self.runTurn(
                        prompt: prompt, model: model, effort: effort, system: system,
                        resume: resume, configuration: configuration,
                        continuation: continuation
                    )
                    if outcome == .staleSession {
                        self.resetSession()
                        if resume != nil { continuation.yield(.right(.sessionLost)) }
                        _ = try await self.runTurn(
                            prompt: prompt, model: model, effort: effort, system: system,
                            resume: nil, configuration: configuration,
                            continuation: continuation
                        )
                    }
                } catch is CancellationError {
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
                    keepWarm(warm.adopting(session: sessionID))
                    return .finished
                }
            }
        } catch {
            warm.terminate()
            throw error
        }

        warm.terminate()
        let detail = warm.errorText()

        if warm.key.session != nil, !emittedText, Self.isMissingSession(detail) {
            logger.info("Resumed session was gone; starting a fresh one")
            return .staleSession
        }

        throw ChatError.claudeCodeFailed(
            detail.isEmpty ? "Claude Code stopped without answering" : String(detail.suffix(400))
        )
    }

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

    public func stopWarmProcess() {
        stateLock.withLock {
            _warm?.terminate()
            _warm = nil
        }
    }

    static func isMissingSession(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains(phraseClaudeCodeUsesWhenTheResumedSessionIsGone)
    }

    private static func contentBlocks(of object: [String: Any]) -> [[String: Any]] {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else { return [] }
        return content
    }

    static func isPermissionRefusal(_ message: String, tool: String = "") -> Bool {
        var phrases = phrasesClaudeCodeUsesWhenItRefusesATool
        if BrowserTools.isBrowserTool(tool) {
            phrases.append(phraseTheBrowserToolsUseWhichIsTooBroadForAnyOtherTool)
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

    static func describe(
        tool name: String,
        input: [String: Any],
        message: String = ""
    ) -> DeniedTool {
        let directory = Option.fromOptional(
            isDirectoryRefusal(message)
                ? blockedDirectory(tool: name, input: input, message: message)
                : nil
        )
        if name == "Bash", let command = input["command"] as? String {
            return DeniedTool(
                name: name,
                target: .some(command),
                rules: bashPermissionRules(for: command),
                directory: directory
            )
        }
        let target = Option.fromOptional(
            (input["file_path"] as? String)
                ?? (input["path"] as? String)
                ?? (input["url"] as? String)
        )
        return DeniedTool(name: name, target: target, rules: [name], directory: directory)
    }

    func handle(line: String) -> [ChatStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return [] }

        switch type {
        case "system": return systemLine(object)
        case "assistant": return toolCalls(in: object)
        case "user": return refusals(in: object)
        case "stream_event": return streamEvents(in: object)
        case "result": return [completion(from: object)]
        default: return []
        }
    }

    private func systemLine(_ object: [String: Any]) -> [ChatStreamEvent] {
        switch object["subtype"] as? String {
        case "init": return adoptSession(from: object)
        case "task_started": return Self.subagentStarted(object)
        case "task_progress": return Self.subagentProgress(object)
        case "task_notification": return Self.subagentFinished(object)
        default: return []
        }
    }

    static func subagentStarted(_ object: [String: Any]) -> [ChatStreamEvent] {
        guard let id = object["task_id"] as? String else { return [] }
        return [.subagentStarted(SubagentTask(
            id: id,
            kind: object["subagent_type"] as? String ?? "sub-agent",
            detail: object["description"] as? String ?? ""
        ))]
    }

    static func subagentProgress(_ object: [String: Any]) -> [ChatStreamEvent] {
        guard let id = object["task_id"] as? String else { return [] }
        return [.subagentProgress(SubagentTask(
            id: id,
            kind: object["subagent_type"] as? String ?? "sub-agent",
            detail: object["description"] as? String ?? "",
            lastTool: Option.fromOptional(object["last_tool_name"] as? String)
        ))]
    }

    static func subagentFinished(_ object: [String: Any]) -> [ChatStreamEvent] {
        guard let id = object["task_id"] as? String else { return [] }
        return [.subagentFinished(SubagentOutcome(
            id: id,
            status: object["status"] as? String ?? "finished",
            summary: object["summary"] as? String ?? ""
        ))]
    }

    static func origin(of object: [String: Any]) -> ActivityOrigin {
        (object["parent_tool_use_id"] as? String).map { .subagent($0) } ?? .main
    }

    private func adoptSession(from object: [String: Any]) -> [ChatStreamEvent] {
        guard object["subtype"] as? String == "init" else { return [] }
        stateLock.withLock {
            if let id = object["session_id"] as? String { _sessionID = id }
            if let model = object["model"] as? String { _reportedModel = model }
        }
        return []
    }

    private func toolCalls(in object: [String: Any]) -> [ChatStreamEvent] {
        Self.contentBlocks(of: object)
            .filter { $0["type"] as? String == "tool_use" }
            .compactMap { block in
                guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
                let input = block["input"] as? [String: Any] ?? [:]
                stateLock.withLock { _pendingToolUses[id] = (name, input) }
                return .activity(AgentActivity(
                    kind: .tool,
                    detail: Self.activityDetail(tool: name, input: input),
                    origin: Self.origin(of: object)
                ))
            }
    }

    private func refusals(in object: [String: Any]) -> [ChatStreamEvent] {
        Self.contentBlocks(of: object)
            .filter { $0["type"] as? String == "tool_result" && $0["is_error"] as? Bool == true }
            .compactMap { block in
                guard let id = block["tool_use_id"] as? String,
                      let call = stateLock.withLock({ _pendingToolUses[id] })
                else { return nil }
                let message = String(describing: block["content"] ?? "")
                guard Self.isPermissionRefusal(message, tool: call.name)
                        || isDirectoryRefusal(message)
                else { return nil }
                stateLock.withLock { _pendingToolUses.removeValue(forKey: id) }
                return .toolDenied(
                    Self.describe(tool: call.name, input: call.input, message: message)
                )
            }
    }

    private func streamEvents(in object: [String: Any]) -> [ChatStreamEvent] {
        guard let event = object["event"] as? [String: Any] else { return [] }
        guard case .main = Self.origin(of: object) else { return [] }

        if event["type"] as? String == "content_block_start",
           let block = event["content_block"] as? [String: Any] {
            switch block["type"] as? String {
            case "thinking":
                return [.activity(AgentActivity(kind: .thinking, detail: "Thinking"))]
            case "text":
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
        let cost = object["total_cost_usd"] as? Double ?? 0
        let window = Self.contextWindow(of: object)
        let usage = Option.fromOptional(object["usage"] as? [String: Any]).map {
            ChatUsage(
                inputTokens: $0["input_tokens"] as? Int ?? 0,
                outputTokens: $0["output_tokens"] as? Int ?? 0,
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

    static func contextWindow(of object: [String: Any]) -> Int? {
        guard let models = object["modelUsage"] as? [String: Any] else { return nil }
        let windowsReportedPerModel = models.values
            .compactMap { ($0 as? [String: Any])?["contextWindow"] as? Int }
        let largestSoTheBarCannotLookFullerThanItIs = windowsReportedPerModel.max()
        return largestSoTheBarCannotLookFullerThanItIs
    }

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
            return .left(text.isEmpty ? "The installer exited \(process.terminationStatus)." : text)
        }
        return .right(text)
    }

    static func launchArguments(
        model: Option<ChatModel>,
        effort: Option<Effort>,
        system: Option<String>,
        resume: String?,
        configuration: Configuration
    ) -> [String] {
        var arguments = [
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", configuration.permissionMode
        ]
        if configuration.browserEnabled { arguments += ["--chrome"] }
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

    static let keysTheChildNeedsFromOurEnvironment = ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "SHELL"]

    static let keyThatWouldBillTheirAPICreditInsteadOfTheirSubscription = "ANTHROPIC_API_KEY"

    static func childEnvironment(
        for installation: ClaudeCodeInstallation,
        loginPath: Option<String> = LoginShellPath.resolve()
    ) -> [String: String] {
        let parent = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]
        for key in Self.keysTheChildNeedsFromOurEnvironment {
            if let value = parent[key] { environment[key] = value }
        }
        environment["PATH"] = LoginShellPath.merged(
            binaryDirectory: installation.executableURL.deletingLastPathComponent().path,
            loginPath: loginPath,
            inherited: Option.fromOptional(parent["PATH"])
        )
        environment.removeValue(forKey: Self.keyThatWouldBillTheirAPICreditInsteadOfTheirSubscription)
        return environment
    }
}
