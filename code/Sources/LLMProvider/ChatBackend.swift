import FunctionalCore
import Foundation

public protocol WorkspaceScopedProvider: AnyObject, Sendable {
    func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?)
    func resetConversation()
    var currentSessionID: String? { get }
    func adoptSession(_ id: String?)
    var hasWorkspaceTools: Bool { get }
    var supportsBrowser: Bool { get }
    func setBrowserEnabled(_ enabled: Bool)
    func stopWarmProcess()
}

public extension WorkspaceScopedProvider {
    var supportsBrowser: Bool { false }
    func setBrowserEnabled(_ enabled: Bool) {}
    func stopWarmProcess() {}
}

extension ClaudeCodeProvider: WorkspaceScopedProvider {
    public func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?) {
        var updated = configuration
        updated.workingDirectory = workingDirectory
        updated.additionalDirectories = additionalDirectories
        if let allowedTools { updated.allowedTools = allowedTools }
        configuration = updated
    }

    public func resetConversation() { resetSession() }

    public var currentSessionID: String? { sessionID }

    public func adoptSession(_ id: String?) { adopt(session: id) }

    public var hasWorkspaceTools: Bool { true }

    public var supportsBrowser: Bool { true }

    public func setBrowserEnabled(_ enabled: Bool) {
        var updated = configuration
        guard updated.browserEnabled != enabled else { return }
        updated.browserEnabled = enabled
        configuration = updated
    }
}

public final class ChatBackend: ChatProvider, WorkspaceScopedProvider, VendorBackend, SkillInstalling, @unchecked Sendable {
    private let detector: ClaudeCodeDetector
    private var _runtime: VendorRuntime
    private let lock = NSLock()
    private var _provider: VendorProvider?
    private var _pending: (workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?)?
    private var _pendingBrowser = false
    private var _pendingSession: String?

    public init(detector: ClaudeCodeDetector, runtime: VendorRuntime = .claudeCode) {
        self.detector = detector
        self._runtime = runtime
        detector.observe { [weak self] availability in self?.adopt(availability) }
    }

    public convenience init(
        locator: ClaudeCodeLocator = ClaudeCodeLocator(),
        runtime: VendorRuntime = .claudeCode
    ) {
        self.init(detector: ClaudeCodeDetector(locator: locator), runtime: runtime)
    }

    public var vendor: AIVendor { lock.withLock { _runtime }.vendor }

    public func use(runtime: VendorRuntime, installation: AgentInstallation?) {
        let previous: VendorProvider? = lock.withLock {
            let old = _provider
            _runtime = runtime
            _pendingSession = nil
            _provider = installation.map { runtime.makeProvider($0) }
            if let built = _provider, let pending = _pending {
                built.prepare(
                    workingDirectory: pending.workingDirectory,
                    additionalDirectories: pending.additionalDirectories,
                    allowedTools: pending.allowedTools
                )
            }
            return old
        }
        previous?.stopWarmProcess()
    }

    public var availability: ClaudeCodeAvailability? { detector.availability }

    public var installation: ClaudeCodeInstallation? { detector.installation }

    @discardableResult
    public func resolveOffTheMainThread() -> ClaudeCodeAvailability {
        let found = detector.resolveOffTheMainThread()
        adopt(found)
        return found
    }

    private var onlyTheClaudeRuntimeIsFoundBySearching: Bool {
        lock.withLock { _runtime.vendor.id } == AIVendor.claudeCode.id
    }

    private func adopt(_ availability: ClaudeCodeAvailability) {
        guard case .available(let installation) = availability else { return }
        lock.lock()
        defer { lock.unlock() }
        guard _provider == nil, _runtime.vendor.id == AIVendor.claudeCode.id else { return }

        let provider = _runtime.makeProvider(installation.agent)
        if let pending = _pending {
            provider.prepare(
                workingDirectory: pending.workingDirectory,
                additionalDirectories: pending.additionalDirectories,
                allowedTools: pending.allowedTools
            )
        }
        provider.setBrowserEnabled(_pendingBrowser)
        if let session = _pendingSession { provider.adoptSession(session) }
        _provider = provider
    }

    public func stream(
        messages: [ChatMessage],
        model: Option<ChatModel>,
        effort: Option<Effort>,
        maxTokens: Int,
        system: Option<String>
    ) -> ChatStream {
        if onlyTheClaudeRuntimeIsFoundBySearching { resolveOffTheMainThread() }
        guard let provider = lock.withLock({ _provider }) else {
            return ChatStream { continuation in
                continuation.yield(.left(.claudeCodeNotFound))
                continuation.finish()
            }
        }
        return provider.stream(
            messages: messages,
            model: model,
            effort: effort,
            maxTokens: maxTokens,
            system: system
        )
    }

    public func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?) {
        let provider: VendorProvider? = lock.withLock {
            _pending = (workingDirectory, additionalDirectories, allowedTools)
            return _provider
        }
        provider?.prepare(
            workingDirectory: workingDirectory,
            additionalDirectories: additionalDirectories,
            allowedTools: allowedTools
        )
    }

    public var currentSessionID: String? {
        lock.withLock { _provider?.currentSessionID ?? _pendingSession }
    }

    public func adoptSession(_ id: String?) {
        let provider: VendorProvider? = lock.withLock {
            _pendingSession = id
            return _provider
        }
        provider?.adoptSession(id)
    }

    public func resetConversation() {
        lock.withLock { _pendingSession = nil }
        lock.withLock { _provider }?.resetConversation()
    }

    public var supportsBrowser: Bool {
        lock.withLock { _runtime.vendor.supportsBrowser && _provider != nil }
    }

    public func setBrowserEnabled(_ enabled: Bool) {
        let provider: VendorProvider? = lock.withLock {
            _pendingBrowser = enabled
            return _provider
        }
        provider?.setBrowserEnabled(enabled)
    }

    public func stopWarmProcess() {
        lock.withLock { _provider }?.stopWarmProcess()
    }

    public func installSkill(named plugin: String) async -> Either<String, String> {
        let maker = vendor
        guard maker.supportsSkills else {
            return .left("\(maker.displayName) can't install skills.")
        }
        guard let provider = lock.withLock({ _provider }) else {
            return .left("\(maker.displayName) isn't available.")
        }
        return await provider.installSkill(named: plugin)
    }

    public var inheritedDefaults: ClaudeCodeDefaults {
        let liveHalfFromThisCharactersOwnSession = Option.fromOptional(lock.withLock { _provider }?.reportedModel)
            .flatMap { Option.fromOptional($0) }^
            .flatMap(ChatModel.named)^
        let fileHalfReadOncePerMachine = detector.diskDefaults
        return ClaudeCodeDefaults(
            model: liveHalfFromThisCharactersOwnSession.orElse(fileHalfReadOncePerMachine.model),
            effort: fileHalfReadOncePerMachine.effort
        )
    }

    public var hasWorkspaceTools: Bool {
        lock.withLock { _provider } != nil
    }
}
