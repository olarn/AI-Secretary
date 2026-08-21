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
    /// Applies to subsequent turns, not the one in flight.
    func setBrowserEnabled(_ enabled: Bool)
    /// Ends any process the backend is keeping warm between turns.
    ///
    /// Needed because a process that no longer exits after each turn is not
    /// ended by anything else: quitting the app or deleting a character would
    /// otherwise leave one running with nothing attached to it. The session
    /// itself survives — the next turn resumes it by id and simply pays the
    /// cold start again.
    func stopWarmProcess()
}

/// Defaults for backends that have no browser to offer, so a provider only
/// implements this when it means something.
public extension WorkspaceScopedProvider {
    var supportsBrowser: Bool { false }
    func setBrowserEnabled(_ enabled: Bool) {}
    /// Nothing kept, nothing to end — true of every backend but the real one.
    func stopWarmProcess() {}
}

extension ClaudeCodeProvider: WorkspaceScopedProvider {
    /// Changing the directory no longer drops the session.
    ///
    /// It used to, on the belief that Claude Code scoped session lookup to the
    /// working directory — resuming from elsewhere failing with "No
    /// conversation found with session ID". Measured against 2.1.220 on
    /// 2026-08-06 that is not true: a session created in one directory resumes
    /// from another and still remembers.
    ///
    /// The pre-emptive reset had to go because it silently beat Chat History.
    /// Reopening a conversation adopts its session; resolving the project on
    /// the first turn then moved the directory and threw the session away
    /// before it was ever used — so the thread came back on screen with none
    /// of it behind the answers, and nothing said so, because no resume was
    /// even attempted.
    ///
    /// Trying and failing is strictly better than not trying: a session that
    /// really has gone comes back as `.staleSession`, which starts a fresh one
    /// *and* says so. Directory and tools are rebuilt into the argv on every
    /// turn regardless — the session only carries what was said.
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

    /// Turning the browser on or off changes the argv of the next turn, and
    /// nothing else — the session is kept.
    ///
    /// It used to be dropped here, on the belief that a resumed session keeps
    /// the tools it was created with. Measured against Claude Code 2.1.220 on
    /// 2026-08-06 and the belief is false: a session started with no `--chrome`
    /// and resumed *with* it reports `claude-in-chrome` connected and runs its
    /// tools. The reset cost two things every time browsing was switched on
    /// mid-conversation — everything said before it, and the browser's tab
    /// group, which the extension binds to the Claude Code session. A new
    /// session is a new group, in a new window, which is what "it opens a new
    /// tab group every time" turned out to be.
    public func setBrowserEnabled(_ enabled: Bool) {
        var updated = configuration
        guard updated.browserEnabled != enabled else { return }
        updated.browserEnabled = enabled
        configuration = updated
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
public final class ChatBackend: ChatProvider, WorkspaceScopedProvider, VendorBackend, SkillInstalling, @unchecked Sendable {
    /// Where Claude Code is. Shared with every other backend in the app — see
    /// `ClaudeCodeDetector` for why that half does not belong here.
    private let detector: ClaudeCodeDetector
    /// How to build this character's provider once the tool has been found.
    private let runtime: VendorRuntime
    private let lock = NSLock()
    /// This backend's own handle on Claude Code: its own session, working
    /// directory, allowlist and browser flag. One per character, which is the
    /// whole reason the detector is not one per character.
    private var _provider: VendorProvider?
    private var _pending: (workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?)?
    private var _pendingBrowser = false
    /// A session adopted before Claude Code had been found yet.
    ///
    /// Reopening a conversation straight after launch is the ordinary case —
    /// it is why the menu exists — and detection has usually not finished by
    /// then. Held here and applied the moment the provider appears, the same
    /// way the working directory is.
    private var _pendingSession: String?

    /// The maker is injected rather than named inside, so a second one is a
    /// different argument at the call site and not a branch in here.
    public init(detector: ClaudeCodeDetector, runtime: VendorRuntime = .claudeCode) {
        self.detector = detector
        self.runtime = runtime
        // Whoever pays for detection, every backend gets the answer — including
        // one built after the search already finished, which `observe` delivers
        // to immediately. Without that, a character created later would sit
        // with no provider until something called `resolve` on her in
        // particular.
        detector.observe { [weak self] availability in self?.adopt(availability) }
    }

    /// For a backend that answers to nobody else — a test, or a one-off. The
    /// app hands every character the same detector instead.
    public convenience init(
        locator: ClaudeCodeLocator = ClaudeCodeLocator(),
        runtime: VendorRuntime = .claudeCode
    ) {
        self.init(detector: ClaudeCodeDetector(locator: locator), runtime: runtime)
    }

    /// Which maker this character's work runs through.
    public var vendor: AIVendor { runtime.vendor }

    /// Detection result, or nil if we haven't looked yet.
    public var availability: ClaudeCodeAvailability? { detector.availability }

    /// Which copy of Claude Code is in use, once detection has run.
    public var installation: ClaudeCodeInstallation? { detector.installation }

    /// **Never call this on the main thread** — resolving can launch a login
    /// shell. Idempotent, so a background task may call it freely.
    @discardableResult
    public func resolve() -> ClaudeCodeAvailability {
        let found = detector.resolve()
        // Belt and braces with the observer installed at init: `adopt` is
        // idempotent, and this makes the synchronous path — `stream` calling
        // `resolve` on the first turn — hold a provider by the time it returns,
        // without depending on observer ordering.
        adopt(found)
        return found
    }

    /// Carries over anything chosen while there was nothing yet to carry it to.
    private func adopt(_ availability: ClaudeCodeAvailability) {
        guard case .available(let installation) = availability else { return }
        lock.lock()
        defer { lock.unlock() }
        guard _provider == nil else { return }

        let provider = runtime.makeProvider(installation.agent)
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

    // MARK: - ChatProvider

    public func stream(
        messages: [ChatMessage],
        model: Option<ChatModel>,
        effort: Option<Effort>,
        maxTokens: Int,
        system: Option<String>
    ) -> ChatStream {
        resolve()
        guard let provider = lock.withLock({ _provider }) else {
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

    /// Forwarded, not defaulted.
    ///
    /// These had default implementations on the protocol for a while, and this
    /// wrapper — the only conformer the app actually runs — silently inherited
    /// them. Every conversation was archived with no session, so reopening one
    /// restored the words and nothing else, while the tests passed because the
    /// test double implemented them properly. No defaults now: a new backend
    /// has to say what it does here.
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

    /// Two conditions, and both have to hold: the maker must have a browser to
    /// offer at all, and its tool must have been found. Whether we have one
    /// isn't known until detection has run, so the preference is remembered
    /// either way and applied when the provider appears, exactly as the working
    /// directory is.
    public var supportsBrowser: Bool {
        runtime.vendor.supportsBrowser && lock.withLock { _provider } != nil
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

    // MARK: - SkillInstalling

    /// Forwarded, and it was not before.
    ///
    /// `ClaudeCodeProvider` has always conformed, but the object the
    /// orchestrator holds is this wrapper, which did not — so the `as?
    /// SkillInstalling` test in `installSkillAndRetry` failed every time and the
    /// character answered "I can't install skills without Claude Code" while
    /// Claude Code sat right there, found and working. Nothing surfaced it
    /// because the refusal is a plausible sentence.
    public func installSkill(named plugin: String) async -> Either<String, String> {
        guard runtime.vendor.supportsSkills else {
            return .left("\(runtime.vendor.displayName) can't install skills.")
        }
        guard let provider = lock.withLock({ _provider }) else {
            return .left("\(runtime.vendor.displayName) isn't available.")
        }
        return await provider.installSkill(named: plugin)
    }

    /// What the user's own Claude Code is set up to use — read from their
    /// settings, then replaced by whatever a live session reports.
    public var inheritedDefaults: ClaudeCodeDefaults {
        let live = Option.fromOptional(lock.withLock { _provider }?.reportedModel)
            .flatMap { Option.fromOptional($0) }^
            .flatMap(ChatModel.named)^
        // The live half is this character's own session reporting what it ran
        // on; the file half is the machine's, so it is read once by the
        // detector rather than once per character.
        let onDisk = detector.diskDefaults
        return ClaudeCodeDefaults(model: live.orElse(onDisk.model), effort: onDisk.effort)
    }

    /// False until detection finishes, and false when falling back to the API
    /// provider — that one really can't look at anything itself.
    public var hasWorkspaceTools: Bool {
        lock.withLock { _provider } != nil
    }
}
