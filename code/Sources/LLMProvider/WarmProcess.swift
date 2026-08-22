import Foundation

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

        drainErrors()
    }

    private func drainErrors() {
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.errorLock.withLock {
                self.collectedErrors.append(data)
                if self.collectedErrors.count > Self.stderrTailKeptBecauseAnAfternoonOfWarningsIsNotAnExplanation * 2 {
                    self.collectedErrors = self.collectedErrors
                        .suffix(Self.stderrTailKeptBecauseAnAfternoonOfWarningsIsNotAnExplanation)
                }
            }
        }
    }

    var isRunning: Bool { process.isRunning }

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
        drainErrors()
    }

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
        closingStdinIsThePoliteEndingBecauseTheCLIExitsOnEndOfInput()
        if process.isRunning { process.terminate() }
    }

    private func closingStdinIsThePoliteEndingBecauseTheCLIExitsOnEndOfInput() {
        try? input.fileHandleForWriting.close()
    }

    static let stderrTailKeptBecauseAnAfternoonOfWarningsIsNotAnExplanation = 32 * 1024
}
