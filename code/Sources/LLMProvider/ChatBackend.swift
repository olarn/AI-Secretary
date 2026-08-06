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
    /// The backend's own handle on the current thread, if it has one.
    ///
    /// Needed to put a conversation away: the words are ours, but what the
    /// model remembers lives on the other side of this and can only be
    /// recovered by name.
    var currentSessionID: String? { get }
    /// Continues a thread the backend already holds. `nil` starts fresh.
    ///
    /// The counterpart to `resetConversation`, and the reason reopening an old
    /// conversation restores more than its text. A session that has since been
    /// cleaned up simply fails to resume and the backend starts over, so this
    /// is a request rather than a guarantee — callers must not promise the
    /// person their context is back until a turn has actually used it.
    func adoptSession(_ id: String?)
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
    /// This was written believing Claude Code scoped session lookup to the
    /// working directory, so that resuming from elsewhere failed with "No
    /// conversation found with session ID". Measured against 2.1.220 on
    /// 2026-08-06 that is **not** true: a session created in one directory
    /// resumes from another and still remembers. The reset stays anyway, for
    /// the reason that survives the correction — a session carries the tools
    /// and the directory it was created with, and silently continuing a thread
    /// that believes it is somewhere else is worse than starting a clean one
    /// the person can see beginning.
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

    public var currentSessionID: String? { sessionID }

    public func adoptSession(_ id: String?) { adopt(session: id) }

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

/// Runs a turn through the person's own Claude Code.
///
/// There is no second path. The app used to fall back to a Claude API key kept
/// in the Keychain, which meant a turn could quietly run on the person's API
/// billing instead of their Claude Code subscription, and meant two answers to
/// "where did this reply come from". Now: Claude Code, or an honest refusal.
///
/// Detection is deliberately lazy. Resolving can mean launching a login shell,
/// which is far too slow to do while the app is starting up, so the first turn
/// (or an explicit background refresh) pays for it and everything after reads a
/// cached answer.
public final class ChatBackend: ChatProvider, WorkspaceScopedProvider, @unchecked Sendable {
    private let locator: ClaudeCodeLocator
    private let lock = NSLock()
    private var _availability: ClaudeCodeAvailability?
    private var _claudeCode: ClaudeCodeProvider?
    private var _pending: (workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?)?
    private var _pendingBrowser = false
    /// A session adopted before Claude Code had been found yet.
    ///
    /// Reopening a conversation straight after launch is the ordinary case —
    /// it is why the menu exists — and detection has usually not finished by
    /// then. Held here and applied the moment the provider appears, the same
    /// way the working directory is.
    private var _pendingSession: String?
    private var _observer: (@Sendable (ClaudeCodeAvailability) -> Void)?
    private var _diskDefaults: ClaudeCodeDefaults?

    public init(locator: ClaudeCodeLocator = ClaudeCodeLocator()) {
        self.locator = locator
    }

    /// Detection result, or nil if we haven't looked yet.
    public var availability: ClaudeCodeAvailability? {
        lock.withLock { _availability }
    }

    /// Which copy of Claude Code is in use, once detection has run.
    public var installation: ClaudeCodeInstallation? {
        availability?.installation
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
            if let session = _pendingSession { provider.adopt(session: session) }
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
        guard let provider = lock.withLock({ _claudeCode }) else {
            // Nothing to fall back to, and nothing to pretend: say what is
            // missing. The onboarding card says the same thing in the panel.
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

    /// Forwarded, not defaulted.
    ///
    /// These had default implementations on the protocol for a while, and this
    /// wrapper — the only conformer the app actually runs — silently inherited
    /// them. Every conversation was archived with no session, so reopening one
    /// restored the words and nothing else, while the tests passed because the
    /// test double implemented them properly. No defaults now: a new backend
    /// has to say what it does here.
    public var currentSessionID: String? {
        lock.withLock { _claudeCode?.currentSessionID ?? _pendingSession }
    }

    public func adoptSession(_ id: String?) {
        let provider: ClaudeCodeProvider? = lock.withLock {
            _pendingSession = id
            return _claudeCode
        }
        provider?.adoptSession(id)
    }

    public func resetConversation() {
        lock.withLock { _pendingSession = nil }
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
