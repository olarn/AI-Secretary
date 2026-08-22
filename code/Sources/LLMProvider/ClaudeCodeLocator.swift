import Foundation

public struct ClaudeCodeInstallation: Equatable, Sendable {
    public let executableURL: URL
    public let version: String?

    public init(executableURL: URL, version: String? = nil) {
        self.executableURL = executableURL
        self.version = version
    }
}

public enum ClaudeCodeAvailability: Equatable, Sendable {
    case available(ClaudeCodeInstallation)
    case notFound(searched: [String])

    public var installation: ClaudeCodeInstallation? {
        if case .available(let installation) = self { return installation }
        return nil
    }
}

public struct ClaudeCodeLocator: Sendable {
    static let knownPaths = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/usr/bin/claude"
    ]

    private let isExecutable: @Sendable (String) -> Bool
    private let probe: @Sendable (URL) -> String?

    public init(
        isExecutable: (@Sendable (String) -> Bool)? = nil,
        probe: (@Sendable (URL) -> String?)? = nil
    ) {
        self.isExecutable = isExecutable ?? { FileManager.default.isExecutableFile(atPath: $0) }
        self.probe = probe ?? { url in ClaudeCodeLocator.readVersion(of: url) }
    }

    public func locateInKnownPathsWithoutLaunchingAnything() -> ClaudeCodeAvailability {
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

    public func locateEvenIfItCostsALoginShell() -> ClaudeCodeAvailability {
        let fast = locateInKnownPathsWithoutLaunchingAnything()
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

        let deadline = Date().addingTimeInterval(Self.shellProbeTimeoutSoAWedgedDotfileCannotHangUs)
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

    static let shellProbeTimeoutSoAWedgedDotfileCannotHangUs: TimeInterval = 5

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
