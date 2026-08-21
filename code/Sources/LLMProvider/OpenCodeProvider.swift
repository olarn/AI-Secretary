import FunctionalCore
import Foundation
import os

/// Runs a turn through the user's own OpenCode.
///
/// Much smaller than the Claude Code provider, because opencode's `run` is
/// one-shot: a process per turn, one JSON object per line on stdout, and the
/// thread carried between turns by `--session` rather than by keeping anything
/// warm. There is no `--input-format`, so the message is an argument — behind
/// `--`, see `openCodeArguments`.
///
/// **Warning — opencode is not gated by the app's approval cards.** Measured on
/// 2026-08-21 against 1.18.15: `run` created a file with no permission prompt
/// and no refusal event, so there is nothing for the app to turn into a card
/// the way a Claude Code refusal becomes one. The containment is the working
/// directory passed as `--dir` and nothing else. The owner decided to ship it
/// on those terms with the Profile panel saying so plainly; do not quietly
/// present it as equivalent to the Claude path.
public final class OpenCodeProvider: ChatProvider, @unchecked Sendable {
    public struct Configuration: Equatable, Sendable {
        public var workingDirectory: URL?
        /// opencode's own name for an effort level, and provider-specific — a
        /// local model may ignore it entirely, which is why the vendor does not
        /// advertise an effort setting.
        public var variant: String?

        public init(workingDirectory: URL? = nil, variant: String? = nil) {
            self.workingDirectory = workingDirectory
            self.variant = variant
        }
    }

    private let installation: AgentInstallation
    private let logger = Logger(subsystem: "AISecretary", category: "opencode")
    private let lock = NSLock()
    private var _configuration: Configuration
    private var _sessionID: String?
    private var _reportedModel: String?
    private var _running: Process?

    public init(installation: AgentInstallation, configuration: Configuration = Configuration()) {
        self.installation = installation
        self._configuration = configuration
    }

    public var configuration: Configuration {
        get { lock.withLock { _configuration } }
        set { lock.withLock { _configuration = newValue } }
    }

    public var reportedModel: String? { lock.withLock { _reportedModel } }

    // MARK: - ChatProvider

    public func stream(
        messages: [ChatMessage],
        model: Option<ChatModel>,
        effort: Option<Effort>,
        maxTokens: Int,
        system: Option<String>
    ) -> ChatStream {
        // opencode keeps the thread itself, so only the newest message is sent
        // — the same shape the Claude path uses, and for the same reason.
        let prompt = messages.last(where: { $0.role == .user })?.content ?? ""
        return ChatStream { continuation in
            let work = Task { await self.run(prompt: prompt, model: model, into: continuation) }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private func run(
        prompt: String,
        model: Option<ChatModel>,
        into continuation: ChatStream.Continuation
    ) async {
        let settings = configuration
        let arguments = openCodeArguments(
            model: model,
            variant: Option.fromOptional(settings.variant),
            session: Option.fromOptional(lock.withLock { _sessionID }),
            workingDirectory: settings.workingDirectory,
            prompt: prompt
        )
        model.fold({}, { chosen in lock.withLock { self._reportedModel = chosen.id } })

        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = arguments
        process.environment = openCodeEnvironment(for: installation)
        // Never the app's own directory: without `--dir` opencode would work
        // wherever the app happens to have been launched from.
        if let directory = settings.workingDirectory { process.currentDirectoryURL = directory }

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        // Closed rather than inherited. opencode asks nothing in `run` mode, and
        // a child holding the app's stdin open is how a turn hangs forever with
        // nothing on screen.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            continuation.yield(.left(.vendorFailed(vendor: "OpenCode", detail: error.localizedDescription)))
            continuation.finish()
            return
        }
        lock.withLock { _running = process }
        defer { lock.withLock { _running = nil } }

        var carried: [String: String] = [:]
        var usage: Option<ChatUsage> = .none()
        var sawText = false

        // A read failure ends the reading, not the turn: whatever already
        // arrived is still the answer, and the exit status below decides
        // whether it counts.
        do {
            for try await line in output.fileHandleForReading.bytes.lines {
                if Task.isCancelled { break }
                let reading = openCodeReading(line: line, textByPart: carried)
                carried = reading.textByPart
                reading.sessionID.fold({}, { id in self.lock.withLock { self._sessionID = id } })
                reading.usage.fold({}, { usage = .some($0) })
                for event in reading.events {
                    if case .textDelta = event { sawText = true }
                    continuation.yield(.right(event))
                }
            }
        } catch {
            logger.error("opencode stdout ended early: \(error.localizedDescription, privacy: .public)")
        }

        process.waitUntilExit()
        let detail = String(
            decoding: (try? errors.fileHandleForReading.readToEnd()) ?? Data(), as: UTF8.self
        )
        guard process.terminationStatus == 0 || sawText else {
            // Said whole rather than classified: opencode's failures are its
            // own — a provider that is not configured, a local server that is
            // not running — and inventing categories for them would be guessing
            // at text this app has never seen.
            let reason = detail.isEmpty
                ? "OpenCode exited \(process.terminationStatus)."
                : String(detail.suffix(400))
            continuation.yield(.left(.vendorFailed(vendor: "OpenCode", detail: reason)))
            continuation.finish()
            return
        }
        continuation.yield(.right(.completed(stopReason: .none(), usage: usage)))
        continuation.finish()
    }
}

// MARK: - The seams the app talks to

extension OpenCodeProvider: VendorProvider {
    public func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?) {
        var updated = configuration
        updated.workingDirectory = workingDirectory
        configuration = updated
        // `additionalDirectories` and `allowedTools` are deliberately dropped.
        // opencode has no `--add-dir` and no allowlist flag, so accepting them
        // and doing nothing is the honest reading of this call: the only
        // containment it has is `--dir`, which is why the panel says so.
    }

    public func resetConversation() { lock.withLock { _sessionID = nil } }

    public var currentSessionID: String? { lock.withLock { _sessionID } }

    public func adoptSession(_ id: String?) { lock.withLock { _sessionID = id } }

    /// True — it reads and writes files in the directory it was given.
    public var hasWorkspaceTools: Bool { true }

    public func stopWarmProcess() {
        lock.withLock { _running }?.terminate()
    }

    public func installSkill(named plugin: String) async -> Either<String, String> {
        // opencode has plugins, but they are not this app's skills and the
        // vendor says so (`supportsSkills: false`), so this is unreachable
        // through `ChatBackend`. Refusing plainly beats pretending.
        .left("OpenCode doesn't install this app's skills.")
    }
}

/// The same small environment the Claude path uses, minus the Anthropic key
/// rule, which does not apply: opencode reads its own credentials from its own
/// files, and the app never handles them.
func openCodeEnvironment(
    for installation: AgentInstallation,
    loginPath: Option<String> = LoginShellPath.resolve()
) -> [String: String] {
    let parent = ProcessInfo.processInfo.environment
    var environment: [String: String] = [:]
    for key in ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "SHELL"] {
        if let value = parent[key] { environment[key] = value }
    }
    // opencode drives other programs too — a local model server, node for a
    // plugin — so it needs the user's real PATH rather than launchd's.
    environment["PATH"] = LoginShellPath.merged(
        binaryDirectory: installation.executableURL.deletingLastPathComponent().path,
        loginPath: loginPath,
        inherited: Option.fromOptional(parent["PATH"])
    )
    return environment
}
