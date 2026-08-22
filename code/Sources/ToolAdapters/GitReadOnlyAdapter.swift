import FunctionalCore
import Foundation
import ProjectRegistry
import os

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

    private static let environmentWithNothingInheritedThatCouldRedirectGit = [
        "PATH": "/usr/bin:/bin",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_OPTIONAL_LOCKS": "0"
    ]

    private func allowlistedArguments(for operation: CodeToolOperation) -> [String] {
        switch operation {
        case .status: return ["status", "--porcelain=v1", "--branch"]
        case .diffStat: return ["diff", "--stat"]
        case .currentBranch: return ["branch", "--show-current"]
        case .recentLog: return ["log", "--oneline", "-n", "20"]
        }
    }

    public func summary(for operation: CodeToolOperation) -> String {
        "git " + allowlistedArguments(for: operation).joined(separator: " ")
    }

    public func run(
        _ operation: CodeToolOperation,
        in project: Project
    ) -> Either<ToolError, ToolResult> {
        let summary = summary(for: operation)

        return requireGitRepository(project)
            .flatMap { _ in self.requireGitExecutable() }^
            .flatMap { _ in self.launch(arguments: self.allowlistedArguments(for: operation), in: project) }^
            .flatMap { process in self.collect(from: process, summary: summary) }^
    }

    private func requireGitRepository(_ project: Project) -> Either<ToolError, Project> {
        var isDirectory: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory)
        guard found, isDirectory.boolValue else {
            return .left(.projectPathMissing(project.path))
        }

        let gitEntryFileInAWorktreeOrDirectoryOtherwise = project.url.appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: gitEntryFileInAWorktreeOrDirectoryOtherwise)
            ? .right(project)
            : .left(.notAGitRepository(project.path))
    }

    private func requireGitExecutable() -> Either<ToolError, URL> {
        FileManager.default.isExecutableFile(atPath: gitExecutable.path)
            ? .right(gitExecutable)
            : .left(.executableMissing(gitExecutable.path))
    }

    private func launch(
        arguments: [String],
        in project: Project
    ) -> Either<ToolError, RunningCommand> {
        let process = Process()
        process.executableURL = gitExecutable
        process.arguments = arguments
        process.currentDirectoryURL = project.url
        process.environment = Self.environmentWithNothingInheritedThatCouldRedirectGit

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

private struct RunningCommand {
    let process: Process
    let pipe: Pipe
}
