import Foundation

/// Why a Claude Code turn failed, read out of what the process said before it
/// exited.
///
/// The raw text was being shown as-is, which meant the difference between "you
/// are not signed in", "you are out of usage" and "your Wi-Fi is off" was left
/// for the reader to work out of a stack trace. Each of those has a different
/// thing to do about it, and the answer is always in the same place, so it is
/// read here once.
///
/// Matching is on substrings of the CLI's own messages and deliberately
/// forgiving: anything unrecognised stays `.unknown` and the original text is
/// still shown. A wrong guess would be worse than no guess.
public enum ClaudeCodeFailure: Equatable, Sendable {
    /// Installed, but nobody is logged in — or the login expired.
    case notSignedIn
    /// The subscription's limit for the window has been used up.
    case usageLimitReached
    /// Claude Code ran but couldn't reach Anthropic.
    case offline
    /// It couldn't be started at all: missing, not executable, killed by the OS.
    case couldNotStart
    /// It exited without saying anything useful.
    case silentExit(code: Int)
    /// Something else. The detail is all there is.
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

    /// `ClaudeCodeProvider` writes exactly this when the process said nothing.
    private static func exitCode(in detail: String) -> Int? {
        let marker = "exited with code "
        guard let range = detail.range(of: marker) else { return nil }
        return Int(detail[range.upperBound...].prefix(while: \.isNumber))
    }

    /// What the user is told: what went wrong, and what to do about it.
    ///
    /// The first line names the failure in plain words — every one of them says
    /// Claude Code, because "which of my things is broken" is the first
    /// question. The original text follows when it adds anything, so a report
    /// can still be pasted somewhere useful.
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
            It resets on its own; until then, an API key in Settings is the \
            other way in.
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

    /// The CLI's own words, kept under the explanation rather than instead of
    /// it. Empty text adds nothing and is left out entirely.
    private func quoted(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        return "\n\nIt said:\n\n```\n\(raw)\n```"
    }
}
