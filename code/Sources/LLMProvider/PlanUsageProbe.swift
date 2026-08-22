import Foundation
import FunctionalCore

public enum PlanUsageProbe {
    public static let timeoutBecauseAHungCommandMustNotBlockAWindow: Duration = .seconds(20)

    public static func read(
        installation: ClaudeCodeInstallation
    ) async -> Either<ChatError, String> {
        let usageAskedAfterADoubleDashSoItCannotBeReadAsAFlag = ["-p", "--output-format", "text", "--", "/usage"]
        return await run(usageAskedAfterADoubleDashSoItCannotBeReadAsAFlag, installation: installation)
    }

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
            try await Task.sleep(for: timeoutBecauseAHungCommandMustNotBlockAWindow)
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
