import Foundation
import FunctionalCore

/// Asks the user's own Claude Code what is left of their plan.
///
/// `claude -p -- /usage` answers the same figures the interactive `/usage` panel
/// shows — session and weekly percentages, and when each window resets. Going
/// through the CLI rather than calling an endpoint keeps the app's one rule
/// intact: it never handles the user's Claude credentials, it drives the tool
/// that already holds them.
///
/// This is a short-lived process, not part of a turn, so it is deliberately kept
/// away from the streaming path: it must never be able to hold up an answer.
public enum PlanUsageProbe {
    /// How long to wait before giving up. The command normally answers in about
    /// a second; if it hangs there is nothing worth blocking a window for.
    public static let timeout: Duration = .seconds(20)

    /// The raw text, or the left side if the command could not be run. Parsing
    /// is the caller's job — `SecretaryCore.PlanUsageParser` owns the format.
    public static func read(
        installation: ClaudeCodeInstallation
    ) async -> Either<ChatError, String> {
        // After `--` so nothing here can be read as a flag, the same rule the
        // chat path follows for user text.
        await run(["-p", "--output-format", "text", "--", "/usage"], installation: installation)
    }

    /// `claude auth status`, which answers JSON including the subscription tier.
    /// Its reply also carries the account's email and organisation id; only the
    /// tier is ever taken out of it.
    public static func readIdentity(
        installation: ClaudeCodeInstallation
    ) async -> Either<ChatError, String> {
        await run(["auth", "status"], installation: installation)
    }

    private static func run(
        _ arguments: [String],
        installation: ClaudeCodeInstallation
    ) async -> Either<ChatError, String> {
        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = arguments
        process.environment = ClaudeCodeProvider.childEnvironment(for: installation)

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .left(.claudeCodeFailed(error.localizedDescription))
        }

        let reader = Task { () -> String in
            let data = try output.fileHandleForReading.readToEnd() ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
        let watchdog = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
        }
        defer { watchdog.cancel() }

        do {
            let text = try await reader.value
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return .left(.claudeCodeFailed("`/usage` exited \(process.terminationStatus)"))
            }
            return .right(text)
        } catch {
            return .left(.claudeCodeFailed(error.localizedDescription))
        }
    }
}
