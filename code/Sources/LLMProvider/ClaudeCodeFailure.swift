import Foundation

private let markerClaudeCodeProviderWritesWhenTheProcessSaidNothing = "exited with code "

public enum ClaudeCodeFailure: Equatable, Sendable {
    case notSignedIn
    case usageLimitReached
    case offline
    case couldNotStart
    case silentExit(code: Int)
    case unknown

    public static func classify(_ detail: String) -> ClaudeCodeFailure {
        let text = detail.lowercased()
        func mentions(_ needles: [String]) -> Bool {
            needles.contains { text.contains($0) }
        }

        if mentions(["/login", "not logged in", "please log in", "authentication_error",
                     "invalid api key", "oauth token has expired", "unauthorized", "401"]) {
            return .notSignedIn
        }
        if mentions(["usage limit", "rate limit", "429", "quota", "credit balance"]) {
            return .usageLimitReached
        }
        if mentions(["enotfound", "econnrefused", "etimedout", "getaddrinfo",
                     "network", "offline", "connection error", "fetch failed",
                     "could not resolve host"]) {
            return .offline
        }
        if mentions(["no such file", "not executable", "permission denied",
                     "couldn’t be opened", "couldn't be opened", "launch path"]) {
            return .couldNotStart
        }
        if let code = exitCode(in: detail) {
            return .silentExit(code: code)
        }
        return .unknown
    }

    private static func exitCode(in detail: String) -> Int? {
        let marker = markerClaudeCodeProviderWritesWhenTheProcessSaidNothing
        guard let range = detail.range(of: marker) else { return nil }
        return Int(detail[range.upperBound...].prefix(while: \.isNumber))
    }

    public func message(detail: String) -> String {
        let raw = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .notSignedIn:
            return """
            Can't reach Claude Code — it isn't signed in. Open Terminal, run \
            `claude` and sign in with `/login`, then try again.
            """ + quoted(raw)
        case .usageLimitReached:
            return """
            Can't reach Claude Code — your Claude usage limit has been reached. \
            It resets on its own; there's no other way in from here, since I \
            work through your own Claude Code.
            """ + quoted(raw)
        case .offline:
            return """
            Can't reach Claude Code — it started, but couldn't reach Anthropic. \
            Check this Mac's internet connection and try again.
            """ + quoted(raw)
        case .couldNotStart:
            return """
            Can't reach Claude Code — the `claude` command wouldn't start. \
            Check that it is installed and runnable from your own Terminal.
            """ + quoted(raw)
        case .silentExit(let code):
            return """
            Can't reach Claude Code — it stopped with code \(code) and said \
            nothing about why. Running the same request in Terminal usually \
            shows the reason.
            """
        case .unknown:
            return "Claude Code failed." + quoted(raw)
        }
    }

    private func quoted(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        return "\n\nIt said:\n\n```\n\(raw)\n```"
    }
}
