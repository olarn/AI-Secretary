import Foundation

/// A provider whose work is scoped to a directory on this Mac.
///
/// The API-backed provider ignores this; the Claude Code one uses the directory
/// as the process working directory, which is the real containment boundary for
/// everything it can read or run.
public protocol WorkspaceScopedProvider: AnyObject, Sendable {
    /// Applies to the next turn. `allowedTools` of `nil` leaves the current
    /// allowlist alone.
    func prepare(workingDirectory: URL?, allowedTools: [String]?)
    /// Drops any resumed session so the next turn starts a fresh conversation.
    func resetConversation()
}

extension ClaudeCodeProvider: WorkspaceScopedProvider {
    public func prepare(workingDirectory: URL?, allowedTools: [String]?) {
        var updated = configuration
        updated.workingDirectory = workingDirectory
        if let allowedTools { updated.allowedTools = allowedTools }
        configuration = updated
    }

    public func resetConversation() { resetSession() }
}

/// Picks where a turn runs: the user's own Claude Code if it's installed,
/// otherwise the API-key provider.
///
/// Detection is deliberately lazy. Resolving can mean launching a login shell,
/// which is far too slow to do while the app is starting up, so the first turn
/// (or an explicit background refresh) pays for it and everything after reads a
/// cached answer.
public final class ChatBackend: ChatProvider, WorkspaceScopedProvider, @unchecked Sendable {
    public enum Kind: Equatable, Sendable {
        case claudeCode(ClaudeCodeInstallation)
        case apiKey
    }

    private let locator: ClaudeCodeLocator
    private let fallback: ChatProvider
    private let lock = NSLock()
    private var _availability: ClaudeCodeAvailability?
    private var _claudeCode: ClaudeCodeProvider?
    private var _pending: (workingDirectory: URL?, allowedTools: [String]?)?
    private var _observer: (@Sendable (ClaudeCodeAvailability) -> Void)?

    public init(locator: ClaudeCodeLocator = ClaudeCodeLocator(), fallback: ChatProvider) {
        self.locator = locator
        self.fallback = fallback
    }

    /// Detection result, or nil if we haven't looked yet.
    public var availability: ClaudeCodeAvailability? {
        lock.withLock { _availability }
    }

    public var kind: Kind? {
        guard let availability else { return nil }
        if case .available(let installation) = availability { return .claudeCode(installation) }
        return .apiKey
    }

    /// Called on the main thread whenever detection completes, so the UI can
    /// swap an onboarding card for the real chat without polling.
    public func observeAvailability(_ observer: @escaping @Sendable (ClaudeCodeAvailability) -> Void) {
        lock.withLock { _observer = observer }
    }

    /// Runs detection if it hasn't run. Safe to call from a background task;
    /// never call it on the main thread.
    @discardableResult
    public func resolve() -> ClaudeCodeAvailability {
        if let cached = availability { return cached }

        let found = locator.locate()

        let observer: (@Sendable (ClaudeCodeAvailability) -> Void)?
        lock.lock()
        _availability = found
        if case .available(let installation) = found {
            let provider = ClaudeCodeProvider(installation: installation)
            if let pending = _pending {
                provider.prepare(workingDirectory: pending.workingDirectory, allowedTools: pending.allowedTools)
            }
            _claudeCode = provider
        }
        observer = _observer
        lock.unlock()

        observer?(found)
        return found
    }

    // MARK: - ChatProvider

    public func stream(
        messages: [ChatMessage],
        model: ChatModel,
        effort: Effort,
        maxTokens: Int,
        system: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        resolve()
        let provider: ChatProvider = lock.withLock { _claudeCode } ?? fallback
        return provider.stream(
            messages: messages,
            model: model,
            effort: effort,
            maxTokens: maxTokens,
            system: system
        )
    }

    // MARK: - WorkspaceScopedProvider

    /// Stored even before detection finishes, so a directory chosen at startup
    /// still applies to the first turn.
    public func prepare(workingDirectory: URL?, allowedTools: [String]?) {
        let provider: ClaudeCodeProvider? = lock.withLock {
            _pending = (workingDirectory, allowedTools)
            return _claudeCode
        }
        provider?.prepare(workingDirectory: workingDirectory, allowedTools: allowedTools)
    }

    public func resetConversation() {
        lock.withLock { _claudeCode }?.resetConversation()
    }
}
