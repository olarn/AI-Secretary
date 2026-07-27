import Foundation

/// A Claude Code CLI found on this Mac.
public struct ClaudeCodeInstallation: Equatable, Sendable {
    public let executableURL: URL
    /// Version string reported by `claude --version`, when it could be read.
    public let version: String?

    public init(executableURL: URL, version: String? = nil) {
        self.executableURL = executableURL
        self.version = version
    }
}

public enum ClaudeCodeAvailability: Equatable, Sendable {
    case available(ClaudeCodeInstallation)
    /// Not installed, or installed somewhere we didn't look.
    case notFound(searched: [String])

    public var installation: ClaudeCodeInstallation? {
        if case .available(let installation) = self { return installation }
        return nil
    }
}

/// Finds the user's own Claude Code CLI.
///
/// This exists because `PATH` is not usable from a bundled app. An app launched
/// from Finder inherits launchd's environment, which on a default macOS install
/// has no `PATH` set at all — the process gets `/usr/bin:/bin:/usr/sbin:/sbin`.
/// The standard Claude Code install lives in `~/.local/bin`, which is not on
/// that list, so `PATH` lookup finds nothing even when the CLI is installed and
/// working in the user's terminal.
///
/// So we look in the known install locations directly, and fall back to asking
/// the user's login shell where `claude` is — that picks up Homebrew, npm, nvm,
/// mise, and anything else their dotfiles put on `PATH`.
public struct ClaudeCodeLocator: Sendable {
    /// Locations checked before falling back to the login shell, in order.
    /// Paths are relative to the home directory when they start with `~`.
    static let knownPaths = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/usr/bin/claude"
    ]

    /// Both injected so tests can exercise the search order without a real
    /// filesystem and without launching anything.
    private let isExecutable: @Sendable (String) -> Bool
    private let probe: @Sendable (URL) -> String?

    public init(
        isExecutable: (@Sendable (String) -> Bool)? = nil,
        probe: (@Sendable (URL) -> String?)? = nil
    ) {
        self.isExecutable = isExecutable ?? { FileManager.default.isExecutableFile(atPath: $0) }
        self.probe = probe ?? { url in ClaudeCodeLocator.readVersion(of: url) }
    }

    /// Checks only the known locations. Pure `stat` calls — microseconds — so
    /// this is safe to call on the main thread during launch. On a normal
    /// install it already finds the CLI and the slow path never runs.
    public func locateInKnownPaths() -> ClaudeCodeAvailability {
        var searched: [String] = []
        for path in Self.knownPaths {
            let expanded = (path as NSString).expandingTildeInPath
            searched.append(expanded)
            guard isExecutable(expanded) else { continue }
            let url = URL(fileURLWithPath: expanded)
            return .available(ClaudeCodeInstallation(executableURL: url, version: probe(url)))
        }
        return .notFound(searched: searched)
    }

    /// Known locations, then the user's login shell.
    ///
    /// **Not for the main thread.** The shell fallback sources the user's
    /// profile (nvm, mise, rbenv…), which routinely takes hundreds of
    /// milliseconds and occasionally seconds. Blocking launch on it would keep
    /// the character window off screen.
    public func locate() -> ClaudeCodeAvailability {
        let fast = locateInKnownPaths()
        if case .available = fast { return fast }
        guard case .notFound(var searched) = fast else { return fast }

        if let url = loginShellLookup() {
            searched.append("login shell PATH")
            if isExecutable(url.path) {
                return .available(ClaudeCodeInstallation(executableURL: url, version: probe(url)))
            }
        }
        return .notFound(searched: searched)
    }

    /// `$SHELL -l -c 'command -v claude'`. A login shell is required: a
    /// non-interactive shell skips the profile that sets up most version
    /// managers. Capped so a wedged dotfile can't hang us forever.
    private func loginShellLookup() -> URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard isExecutable(shell) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(Self.shellProbeTimeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }

    static let shellProbeTimeout: TimeInterval = 5

    /// Runs `claude --version` and returns the reported version. A failure here
    /// is not fatal — an executable that won't report its version is still worth
    /// trying, and the caller only uses this for display.
    private static func readVersion(of url: URL) -> String? {
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }
}
