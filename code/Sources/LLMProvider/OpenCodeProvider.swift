import FunctionalCore
import Foundation

private let closedSoAChildHoldingOurStdinCannotHangTheTurn = FileHandle.nullDevice
import os

public final class OpenCodeProvider: ChatProvider, @unchecked Sendable {
    public struct Configuration: Equatable, Sendable {
        public var workingDirectory: URL?
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

    public func stream(
        messages: [ChatMessage],
        model: Option<ChatModel>,
        effort: Option<Effort>,
        maxTokens: Int,
        system: Option<String>
    ) -> ChatStream {
        let prompt = openCodePrompt(
            system: system,
            message: messages.last(where: { $0.role == .user })?.content ?? ""
        )
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
        if let directory = settings.workingDirectory { process.currentDirectoryURL = directory }

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = closedSoAChildHoldingOurStdinCannotHangTheTurn

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

extension OpenCodeProvider: VendorProvider {
    public func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?) {
        var updated = configuration
        updated.workingDirectory = workingDirectory
        configuration = updated
        openCodeHasNoFlagForTheseSoAcceptingThemAndDoingNothingIsTheHonestReading(
            additionalDirectories, allowedTools
        )
    }

    private func openCodeHasNoFlagForTheseSoAcceptingThemAndDoingNothingIsTheHonestReading(
        _ additionalDirectories: [URL],
        _ allowedTools: [String]?
    ) {}

    public func resetConversation() { lock.withLock { _sessionID = nil } }

    public var currentSessionID: String? { lock.withLock { _sessionID } }

    public func adoptSession(_ id: String?) { lock.withLock { _sessionID = id } }

    public var hasWorkspaceTools: Bool { true }

    public func stopWarmProcess() {
        lock.withLock { _running }?.terminate()
    }

    public func installSkill(named plugin: String) async -> Either<String, String> {
        .left("OpenCode doesn't install this app's skills.")
    }
}

func openCodeEnvironment(
    for installation: AgentInstallation,
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
    return environment
}
