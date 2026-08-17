import FunctionalCore
import Foundation

/// Where the search for the person's own Claude Code has got to.
///
/// Three states rather than two flags, because the middle one is the whole
/// point: not finding it *yet* is not the same as not having it, and a panel
/// that treats "still looking" as "not installed" tells everyone who launches
/// the app to go and install what they already have.
public enum BackendReadiness: Equatable, Sendable {
    case looking
    case notInstalled
    case ready(version: Option<String>)
}

/// What stands in for the conversation before there is one.
///
/// A pure function in a library target rather than a string in the view,
/// because `AISecretaryApp` is never linked into the test bundle — and this is
/// what that costs when it isn't: the ready line shipped with thirteen literal
/// spaces in the middle of it, left behind when a line break was collapsed into
/// the sentence, and nothing could see it but a person looking at the window
/// (reported 2026-08-17). The tests below assert the whole string, which is the
/// only kind of assertion that catches whitespace.
public func emptyTranscriptHint(_ readiness: BackendReadiness) -> String {
    switch readiness {
    case .looking:
        return "Checking for Claude Code…"
    case .notInstalled:
        return "Install Claude Code and sign in, and I'll be able to work for you."
    case .ready(let version):
        let named = version.map { " (\($0))" }^.getOrElse("")
        // One break, not a blank line. Two beats — what I am, then what to do —
        // so they do not belong on one line, but a paragraph between two short
        // sentences read as a gap rather than as structure (owner, 2026-08-17).
        return """
        Ready — I'll work through your own Claude Code\(named).
        Add a project, then just tell me what you need in your own words.
        """
    }
}
