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

    public func run(_ operation: CodeToolOperation, in project: Project) throws -> ToolResult {
        let args = arguments(for: operation)
        let summary = summary(for: operation)

        try validate(project: project)

        guard FileManager.default.isExecutableFile(atPath: gitExecutable.path) else {
            throw ToolError.executableMissing(gitExecutable.path)
        }

        let process = Process()
        process.executableURL = gitExecutable
        process.arguments = args
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

        do {
            try process.run()
        } catch {
            throw ToolError.launchFailed(error.localizedDescription)
        }

        logger.info("Running \(summary, privacy: .public) in project \(project.name, privacy: .public)")

        let data = readOutput(from: pipe, process: process)
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }

        if process.isRunning {
            process.terminate()
            logger.error("Timed out: \(summary, privacy: .public)")
            throw ToolError.timedOut(seconds: timeoutSeconds)
        }

        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return ToolResult(output: output, exitCode: process.terminationStatus, commandSummary: summary)
    }

    private func validate(project: Project) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ToolError.projectPathMissing(project.path)
        }

        // A worktree stores .git as a file, so accept either kind of entry.
        let gitEntry = project.url.appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: gitEntry) else {
            throw ToolError.notAGitRepository(project.path)
        }
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
