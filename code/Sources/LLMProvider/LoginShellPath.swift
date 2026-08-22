import FunctionalCore
import Foundation

private let loginShellArgumentsBecauseANonInteractiveShellSkipsTheProfile = ["-l", "-c", "echo $PATH"]

public enum LoginShellPath {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedAnswerIfWeHaveLookedYet: Option<Option<String>> = .none()

    static let timeoutSoAWedgedDotfileCannotStallATurn: TimeInterval = 5

    public static func resolve() -> Option<String> {
        lock.lock()
        let memo = cachedAnswerIfWeHaveLookedYet
        lock.unlock()

        if let answer = memo.toOptional() { return answer }

        let found = query()

        lock.lock()
        cachedAnswerIfWeHaveLookedYet = .some(found)
        lock.unlock()
        return found
    }

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

    private static func query() -> Option<String> {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return .none() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = loginShellArgumentsBecauseANonInteractiveShellSkipsTheProfile
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .none()
        }

        let deadline = Date().addingTimeInterval(timeoutSoAWedgedDotfileCannotStallATurn)
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
