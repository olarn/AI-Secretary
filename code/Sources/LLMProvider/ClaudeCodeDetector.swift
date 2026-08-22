import Foundation

public final class ClaudeCodeDetector: @unchecked Sendable {
    private let locator: ClaudeCodeLocator
    private let lock = NSLock()
    private let detectionLock = NSLock()
    private var _availability: ClaudeCodeAvailability?
    private var _observers: [@Sendable (ClaudeCodeAvailability) -> Void] = []
    private var _diskDefaults: ClaudeCodeDefaults?

    public init(locator: ClaudeCodeLocator = ClaudeCodeLocator()) {
        self.locator = locator
    }

    public var availability: ClaudeCodeAvailability? {
        lock.withLock { _availability }
    }

    public var installation: ClaudeCodeInstallation? {
        availability?.installation
    }

    public func observe(_ observer: @escaping @Sendable (ClaudeCodeAvailability) -> Void) {
        let alreadyFinished: ClaudeCodeAvailability? = lock.withLock {
            _observers.append(observer)
            return _availability
        }
        if let alreadyFinished { observer(alreadyFinished) }
    }

    @discardableResult
    public func resolveOffTheMainThread() -> ClaudeCodeAvailability {
        if let alreadyFound = availability { return alreadyFound }

        detectionLock.lock()
        defer { detectionLock.unlock() }
        if let foundWhileWeWaitedForThisLock = availability { return foundWhileWeWaitedForThisLock }

        let found = locator.locateEvenIfItCostsALoginShell()
        warmTheLoginShellPathWhileWeAreAlreadyOffTheMainThread()

        let observers: [@Sendable (ClaudeCodeAvailability) -> Void] = lock.withLock {
            _availability = found
            return _observers
        }
        observers.forEach { $0(found) }
        return found
    }

    private func warmTheLoginShellPathWhileWeAreAlreadyOffTheMainThread() {
        _ = LoginShellPath.resolve()
    }

    public var diskDefaults: ClaudeCodeDefaults {
        if let readOnceForTheWholeMachine = lock.withLock({ _diskDefaults }) {
            return readOnceForTheWholeMachine
        }
        let read = ClaudeCodeDefaults.read()
        lock.withLock { _diskDefaults = read }
        return read
    }
}
