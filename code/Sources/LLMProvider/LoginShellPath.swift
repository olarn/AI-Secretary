import FunctionalCore
import Foundation

/// The `PATH` the user actually has in their terminal.
///
/// An app launched from Finder inherits launchd's environment, where `PATH` is
/// unset — the process gets `/usr/bin:/bin:/usr/sbin:/sbin`. That is enough to
/// launch Claude Code (we find its binary by absolute path), but not enough for
/// the things Claude Code then launches: an MCP server started with `node` or
/// `uvx`, or a Bash command that calls a tool installed by Homebrew, nvm, mise,
/// pyenv. Those all live on a `PATH` set by the user's shell profile.
///
/// Observed failure this fixes: a stdio MCP server configured as
/// `node …/build/index.js` reported `status: "failed"` from the packaged app
/// while working fine from a terminal.
///
/// Resolved once and cached: launching a login shell is slow, and the answer
/// doesn't change while the app runs.
public enum LoginShellPath {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: Option<Option<String>> = .none()

    /// How long to wait for the shell. A wedged dotfile must not stall a turn.
    static let timeout: TimeInterval = 5

    /// Cached across calls; the first one pays for the shell. The doubled
    /// `Option` distinguishes "not looked yet" from "looked, found nothing".
    public static func resolve() -> Option<String> {
        lock.lock()
        let memo = cached
        lock.unlock()

        if let answer = memo.toOptional() { return answer }

        let found = query()

        lock.lock()
        cached = .some(found)
        lock.unlock()
        return found
    }

    /// Combines the directories that matter, most specific first, without
    /// duplicates: where Claude Code itself lives, then the user's own `PATH`,
    /// then the system minimum as a floor.
    public static func merged(
        binaryDirectory: String,
        loginPath: Option<String>,
        inherited: Option<String>
    ) -> String {
        func directories(_ path: Option<String>) -> [String] {
            path.fold({ [] }, { $0.split(separator: ":").map(String.init) })
        }

        var parts: [String] = [binaryDirectory]
        parts.append(contentsOf: directories(loginPath))
        parts.append(contentsOf: directories(inherited))
        parts.append(contentsOf: directories(.some("/usr/bin:/bin:/usr/sbin:/sbin")))

        var seen = Set<String>()
        var ordered: [String] = []
        for part in parts where !part.isEmpty && seen.insert(part).inserted {
            ordered.append(part)
        }
        return ordered.joined(separator: ":")
    }

    /// `$SHELL -l -c 'echo $PATH'`. A login shell is required: a
    /// non-interactive one skips the profile that sets up version managers.
    private static func query() -> Option<String> {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return .none() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .none()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            return .none()
        }

        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? .none() : .some(output)
    }
}
