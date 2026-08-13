import Foundation

/// One Claude Code process, kept alive across turns.
///
/// The measurement that justifies it is on `WarmProcessKey`. What this type
/// adds is the four things a process that no longer exits per turn still has to
/// get right — each of them a way the old one-shot design would silently stop
/// working rather than a detail:
///
/// 1. **Its output is one stream, read in turn-sized pieces.** The iterator is
///    held here, not made per turn, or the second turn would start reading a
///    new stream from a process that only ever had one.
/// 2. **Its stderr is drained continuously.** A pipe nobody reads fills up, and
///    a child blocked writing to a full pipe hangs forever. Over a process that
///    lives for one turn that never happened; over one that lives all afternoon
///    it would.
/// 3. **Death is noticed on the way in.** Writing to a dead process's stdin
///    raises rather than hanging, which is what lets the caller retry once.
/// 4. **Ending it is explicit.** Terminating is how a stopped turn, a changed
///    workspace and a torn-down character all end a session, so it is one
///    method rather than three places calling `terminate`.
final class WarmProcess: @unchecked Sendable {
    let key: WarmProcessKey

    private let process: Process
    private let input: Pipe
    private let errors: Pipe
    private var lines: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator

    private let errorLock = NSLock()
    private var collectedErrors = Data()

    init(process: Process, input: Pipe, output: Pipe, errors: Pipe, key: WarmProcessKey) {
        self.process = process
        self.input = input
        self.errors = errors
        self.key = key
        self.lines = output.fileHandleForReading.bytes.lines.makeAsyncIterator()

        // See 2 above. Bounded, because the only reason to keep it is to
        // explain a failure, and an afternoon of warnings is not an
        // explanation.
        drainErrors()
    }

    /// Keeps stderr moving, and keeps the tail of it in case a failure has to
    /// be explained. Bounded: an afternoon of warnings is not an explanation.
    private func drainErrors() {
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.errorLock.withLock {
                self.collectedErrors.append(data)
                if self.collectedErrors.count > 64 * 1024 {
                    self.collectedErrors = self.collectedErrors.suffix(32 * 1024)
                }
            }
        }
    }

    var isRunning: Bool { process.isRunning }

    /// The same process, now known to be serving this session. A fresh one
    /// mints its own id and only says so in the init event.
    func adopting(session: String?) -> WarmProcess {
        guard key.session != session else { return self }
        return WarmProcess(process: process, input: input, errors: errors, lines: lines, key: WarmProcessKey(
            workingDirectory: key.workingDirectory,
            additionalDirectories: key.additionalDirectories,
            allowedTools: key.allowedTools,
            permissionMode: key.permissionMode,
            browserEnabled: key.browserEnabled,
            model: key.model,
            effort: key.effort,
            system: key.system,
            session: session
        ), errorsSoFar: errorLock.withLock { collectedErrors })
    }

    /// Re-wrapping the same live handles under a new key. Private because
    /// nothing else may build one of these around a process someone else owns.
    private init(
        process: Process,
        input: Pipe,
        errors: Pipe,
        lines: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator,
        key: WarmProcessKey,
        errorsSoFar: Data
    ) {
        self.process = process
        self.input = input
        self.errors = errors
        self.lines = lines
        self.key = key
        self.collectedErrors = errorsSoFar
        // The handler installed by the designated initialiser is still on the
        // same file handle and still holds the *old* wrapper, so it keeps
        // draining — which is what matters — but it appends where nobody will
        // read. Point it here instead.
        drainErrors()
    }

    /// Hands one message to the process. Throws if it is no longer there.
    func send(_ line: String) throws {
        guard process.isRunning else {
            throw ChatError.claudeCodeFailed("Claude Code was no longer running")
        }
        try input.fileHandleForWriting.write(contentsOf: Data(line.utf8))
    }

    func nextLine() async throws -> String? {
        try await lines.next()
    }

    func errorText() -> String {
        errorLock
            .withLock { String(decoding: collectedErrors, as: UTF8.self) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func terminate() {
        errors.fileHandleForReading.readabilityHandler = nil
        // Closing stdin is the polite ending — the CLI treats end of input as
        // the end of the conversation and exits on its own. `terminate` after
        // it, for the case where it does not.
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}
