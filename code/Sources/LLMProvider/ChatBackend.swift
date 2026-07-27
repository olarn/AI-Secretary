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
    /// Whether the backend can actually look at the directory on its own.
    ///
    /// The caller needs this to write the right system prompt. Telling a model
    /// with file tools that it "cannot run commands" makes it ask the user to
    /// paste files it could simply have opened.
    var hasWorkspaceTools: Bool { get }
}

extension ClaudeCodeProvider: WorkspaceScopedProvider {
    /// Changing the directory also drops the session.
    ///
    /// Claude Code scopes session lookup to the working directory, so resuming
    /// a session started elsewhere fails with "No conversation found with
    /// session ID". That is exactly what happens on the normal path here: the
    /// first message runs in the scratch directory, the user then approves a
    /// project, and the next turn would try to resume the scratch session from
    /// inside the project.
    public func prepare(workingDirectory: URL?, allowedTools: [String]?) {
        var updated = configuration
        let moved = updated.workingDirectory?.standardizedFileURL
            != workingDirectory?.standardizedFileURL
        updated.workingDirectory = workingDirectory
        if let allowedTools { updated.allowedTools = allowedTools }
        configuration = updated
        if moved { resetSession() }
    }

    public func resetConversation() { resetSession() }

    public var hasWorkspaceTools: Bool { true }
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

    /// False until detection finishes, and false when falling back to the API
    /// provider — that one really can't look at anything itself.
    public var hasWorkspaceTools: Bool {
        lock.withLock { _claudeCode } != nil
    }
}
