import FunctionalCore
import Foundation
import ProjectRegistry
import os

/// Runs a fixed, read-only set of Git commands inside an approved project
/// directory.
///
/// Safety properties this type is responsible for:
/// - `git` is launched by absolute path, never resolved through `PATH`.
/// - Arguments are passed as an array to `Process`; no shell is involved, so
///   there is no quoting or injection surface.
/// - Argument vectors are hardcoded per operation. User text selects an
///   operation; it never reaches the command line.
/// - The working directory comes only from a registered `Project`, and is
///   verified to exist and contain a `.git` entry before launching.
/// - Output is capped and the process is killed if it exceeds a timeout.
///
/// The checks are rails: each returns the value the next one needs, so nothing
/// launches unless every earlier check produced a right.
public final class GitReadOnlyAdapter: CodeToolAdapter {
    public static let toolIdentifier = "git.readOnly"

    public var toolID: String { Self.toolIdentifier }

    private let gitExecutable: URL
    private let timeoutSeconds: Int
    private let maxOutputBytes: Int
    private let logger = Logger(subsystem: "com.aisecretary.app", category: "GitReadOnlyAdapter")

    public init(
        gitExecutable: URL = URL(fileURLWithPath: "/usr/bin/git"),
        timeoutSeconds: Int = 15,
        maxOutputBytes: Int = 128 * 1024
    ) {
        self.gitExecutable = gitExecutable
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputBytes = maxOutputBytes
    }

    /// The complete allowlist. Anything not described here cannot be run.
    private func arguments(for operation: CodeToolOperation) -> [String] {
        switch operation {
        case .status: return ["status", "--porcelain=v1", "--branch"]
        case .diffStat: return ["diff", "--stat"]
        case .currentBranch: return ["branch", "--show-current"]
        case .recentLog: return ["log", "--oneline", "-n", "20"]
        }
    }

    public func summary(for operation: CodeToolOperation) -> String {
        "git " + arguments(for: operation).joined(separator: " ")
    }

    public func run(
        _ operation: CodeToolOperation,
        in project: Project
    ) -> Either<ToolError, ToolResult> {
        let summary = summary(for: operation)

        return requireGitRepository(project)
            .flatMap { _ in self.requireGitExecutable() }^
            .flatMap { _ in self.launch(arguments: self.arguments(for: operation), in: project) }^
            .flatMap { process in self.collect(from: process, summary: summary) }^
    }

    // MARK: - Rails

    private func requireGitRepository(_ project: Project) -> Either<ToolError, Project> {
        var isDirectory: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory)
        guard found, isDirectory.boolValue else {
            return .left(.projectPathMissing(project.path))
        }

        // A worktree stores .git as a file, so accept either kind of entry.
        let gitEntry = project.url.appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: gitEntry)
            ? .right(project)
            : .left(.notAGitRepository(project.path))
    }

    private func requireGitExecutable() -> Either<ToolError, URL> {
        FileManager.default.isExecutableFile(atPath: gitExecutable.path)
            ? .right(gitExecutable)
            : .left(.executableMissing(gitExecutable.path))
    }

    /// The Foundation edge: `Process.run` throws, and that is the only throw in
    /// this type. Everything after it is a value.
    private func launch(
        arguments: [String],
        in project: Project
    ) -> Either<ToolError, RunningCommand> {
        let process = Process()
        process.executableURL = gitExecutable
        process.arguments = arguments
        process.currentDirectoryURL = project.url
        // Minimal environment: no inherited config that could redirect git.
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_OPTIONAL_LOCKS": "0"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return attempt { try process.run() }
            .mapLeft { ToolError.launchFailed($0.localizedDescription) }^
            .map { _ in
                self.logger.info(
                    "Running git \(arguments.joined(separator: " "), privacy: .public) in \(project.name, privacy: .public)"
                )
                return RunningCommand(process: process, pipe: pipe)
            }^
    }

    private func collect(
        from command: RunningCommand,
        summary: String
    ) -> Either<ToolError, ToolResult> {
        let data = readOutput(from: command.pipe, process: command.process)

        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while command.process.isRunning && Date() < deadline {
            usleep(20_000)
        }

        if command.process.isRunning {
            command.process.terminate()
            logger.error("Timed out: \(summary, privacy: .public)")
            return .left(.timedOut(seconds: timeoutSeconds))
        }

        command.process.waitUntilExit()

        return .right(
            ToolResult(
                output: String(data: data, encoding: .utf8) ?? "",
                exitCode: command.process.terminationStatus,
                commandSummary: summary
            )
        )
    }

    private func readOutput(from pipe: Pipe, process: Process) -> Data {
        var data = Data()
        let handle = pipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count >= maxOutputBytes {
                data = data.prefix(maxOutputBytes)
                if process.isRunning { process.terminate() }
                break
            }
        }
        return data
    }
}

/// One value, so the launch rail can hand both to the collect rail.
private struct RunningCommand {
    let process: Process
    let pipe: Pipe
}
