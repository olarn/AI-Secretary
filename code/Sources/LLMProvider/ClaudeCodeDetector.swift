import Foundation

/// Finds the user's Claude Code once, for the whole app.
///
/// Detection and *using* what was detected used to be the same object. That
/// was fine while there was one conversation, and wrong the moment there are
/// several: a session belongs to one character, but the answer to "where is
/// Claude Code" belongs to the machine. Left together, every character added
/// would pay for the search again — and the search is not cheap. The fast path
/// is a handful of `stat` calls, but the fallback launches the user's login
/// shell, which is slow enough that the app deliberately defers it off the
/// launch path.
///
/// So this half is shared and `ChatBackend` is the half that is not: one
/// detector, one login shell, and a `ClaudeCodeProvider` per character holding
/// her own session, working directory and browser flag.
public final class ClaudeCodeDetector: @unchecked Sendable {
    private let locator: ClaudeCodeLocator
    private let lock = NSLock()
    /// Held separately from `lock` so a second caller waits for the first
    /// caller's answer rather than starting a second search. `lock` is only
    /// ever held for the length of a property read.
    private let detectionLock = NSLock()
    private var _availability: ClaudeCodeAvailability?
    private var _observers: [@Sendable (ClaudeCodeAvailability) -> Void] = []
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

    /// Watches for detection finishing. Several things do: every character's
    /// backend, so it can build its provider, and the app, so it can swap an
    /// onboarding card for the real chat.
    ///
    /// A watcher that arrives *after* detection has already finished is called
    /// straight away rather than left waiting for an event that has been and
    /// gone — which is the ordinary case for a character created later.
    public func observe(_ observer: @escaping @Sendable (ClaudeCodeAvailability) -> Void) {
        let known: ClaudeCodeAvailability? = lock.withLock {
            _observers.append(observer)
            return _availability
        }
        if let known { observer(known) }
    }

    /// **Never call this on the main thread** — the fallback launches the user's
    /// login shell. A second caller waits for the first caller's answer.
    @discardableResult
    public func resolve() -> ClaudeCodeAvailability {
        if let cached = availability { return cached }

        detectionLock.lock()
        defer { detectionLock.unlock() }
        // Read again inside: two characters resolving at once both saw nil
        // above, and the point of this lock is that the second one waits for
        // the first one's answer instead of launching a second login shell.
        if let cached = availability { return cached }

        let found = locator.locate()
        // Same background pass: resolving the login shell is slow and the first
        // turn shouldn't pay for it.
        _ = LoginShellPath.resolve()

        let observers: [@Sendable (ClaudeCodeAvailability) -> Void] = lock.withLock {
            _availability = found
            return _observers
        }
        observers.forEach { $0(found) }
        return found
    }

    /// What the user's own Claude Code is set up to use, read from their
    /// settings file. Read once and kept: it is the machine's answer, not a
    /// character's, and re-reading it per character would be the same file
    /// parsed N times to get the same result.
    public var diskDefaults: ClaudeCodeDefaults {
        if let cached = lock.withLock({ _diskDefaults }) { return cached }
        let read = ClaudeCodeDefaults.read()
        lock.withLock { _diskDefaults = read }
        return read
    }
}
