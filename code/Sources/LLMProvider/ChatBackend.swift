import FunctionalCore
import Foundation

/// A provider whose work is scoped to a directory on this Mac.
///
/// The API-backed provider ignores this; the Claude Code one uses the directory
/// as the process working directory, which is the real containment boundary for
/// everything it can read or run.
public protocol WorkspaceScopedProvider: AnyObject, Sendable {
    /// Applies to the next turn. `allowedTools` of `nil` leaves the current
    /// allowlist alone.
    func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?)
    /// Drops any resumed session so the next turn starts a fresh conversation.
    func resetConversation()
    /// Whether the backend can actually look at the directory on its own.
    ///
    /// The caller needs this to write the right system prompt. Telling a model
    /// with file tools that it "cannot run commands" makes it ask the user to
    /// paste files it could simply have opened.
    var hasWorkspaceTools: Bool { get }
    /// Whether this backend can reach the user's browser at all. Only the
    /// user's own Claude Code can: the extension authenticates against their
    /// subscription, so an API-key backend has no way in.
    var supportsBrowser: Bool { get }
    /// Connects or disconnects the browser for subsequent turns.
    func setBrowserEnabled(_ enabled: Bool)
}

/// Defaults for backends that have no browser to offer, so a provider only
/// implements this when it means something.
public extension WorkspaceScopedProvider {
    var supportsBrowser: Bool { false }
    func setBrowserEnabled(_ enabled: Bool) {}
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
    public func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?) {
        var updated = configuration
        let moved = updated.workingDirectory?.standardizedFileURL
            != workingDirectory?.standardizedFileURL
        updated.workingDirectory = workingDirectory
        updated.additionalDirectories = additionalDirectories
        if let allowedTools { updated.allowedTools = allowedTools }
        configuration = updated
        if moved { resetSession() }
    }

    public func resetConversation() { resetSession() }

    public var hasWorkspaceTools: Bool { true }

    public var supportsBrowser: Bool { true }

    /// Turning the browser on or off changes which tools the next session is
    /// started with, so the current session is dropped — a resumed one keeps
    /// the tools it was created with, and the user would be told the browser
    /// was connected while the model still couldn't see it.
    public func setBrowserEnabled(_ enabled: Bool) {
        var updated = configuration
        guard updated.browserEnabled != enabled else { return }
        updated.browserEnabled = enabled
        configuration = updated
        resetSession()
    }
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
    private var _pending: (workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?)?
    private var _pendingBrowser = false
    private var _observer: (@Sendable (ClaudeCodeAvailability) -> Void)?
    private var _diskDefaults: ClaudeCodeDefaults?

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
        // Same background pass: resolving the login shell is slow and the first
        // turn shouldn't pay for it.
        _ = LoginShellPath.resolve()

        let observer: (@Sendable (ClaudeCodeAvailability) -> Void)?
        lock.lock()
        _availability = found
        if case .available(let installation) = found {
            let provider = ClaudeCodeProvider(installation: installation)
            if let pending = _pending {
                provider.prepare(
                    workingDirectory: pending.workingDirectory,
                    additionalDirectories: pending.additionalDirectories,
                    allowedTools: pending.allowedTools
                )
            }
            provider.setBrowserEnabled(_pendingBrowser)
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
        model: Option<ChatModel>,
        effort: Option<Effort>,
        maxTokens: Int,
        system: Option<String>
    ) -> ChatStream {
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
    public func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?) {
        let provider: ClaudeCodeProvider? = lock.withLock {
            _pending = (workingDirectory, additionalDirectories, allowedTools)
            return _claudeCode
        }
        provider?.prepare(
            workingDirectory: workingDirectory,
            additionalDirectories: additionalDirectories,
            allowedTools: allowedTools
        )
    }

    public func resetConversation() {
        lock.withLock { _claudeCode }?.resetConversation()
    }

    /// Only the user's own Claude Code carries the browser connection, and
    /// whether we have one isn't known until detection has run — so the
    /// preference is remembered either way and applied when the provider
    /// appears, exactly as the working directory is.
    public var supportsBrowser: Bool {
        lock.withLock { _claudeCode } != nil
    }

    public func setBrowserEnabled(_ enabled: Bool) {
        let provider: ClaudeCodeProvider? = lock.withLock {
            _pendingBrowser = enabled
            return _claudeCode
        }
        provider?.setBrowserEnabled(enabled)
    }

    /// What the user's own Claude Code is set up to use — read from their
    /// settings, then replaced by whatever a live session reports.
    public var inheritedDefaults: ClaudeCodeDefaults {
        let live = Option.fromOptional(lock.withLock { _claudeCode }?.reportedModel)
            .flatMap { Option.fromOptional($0) }^
            .flatMap(ChatModel.named)^
        let onDisk = lock.withLock { _diskDefaults } ?? {
            let read = ClaudeCodeDefaults.read()
            lock.withLock { _diskDefaults = read }
            return read
        }()
        return ClaudeCodeDefaults(model: live.orElse(onDisk.model), effort: onDisk.effort)
    }

    /// False until detection finishes, and false when falling back to the API
    /// provider — that one really can't look at anything itself.
    public var hasWorkspaceTools: Bool {
        lock.withLock { _claudeCode } != nil
    }
}
