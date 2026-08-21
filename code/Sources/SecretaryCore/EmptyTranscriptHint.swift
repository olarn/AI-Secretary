import FunctionalCore
import Foundation

/// Where the search for the person's own coding tool has got to.
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
///
/// `makers` are the tools the app can run a turn through, and they arrive as an
/// argument rather than being named here: this line greeted every character
/// with "your own Claude Code", including the ones set to OpenCode, which is
/// the same defect the Model and Effort menus had before they learned to say
/// "the tool's own default" (owner, 2026-08-21). The greeting no longer names a
/// maker at all — which one was found is already in the brackets after it.
public func emptyTranscriptHint(_ readiness: BackendReadiness, makers: [String]) -> String {
    switch readiness {
    case .looking:
        return "Checking for your AI tool…"
    case .notInstalled:
        return "Install \(makerList(makers)) and sign in, and I'll be able to work for you."
    case .ready(let version):
        let named = version.map { " (\($0))" }^.getOrElse("")
        // One break, not a blank line. Two beats — what I am, then what to do —
        // so they do not belong on one line, but a paragraph between two short
        // sentences read as a gap rather than as structure (owner, 2026-08-17).
        return """
        Ready — I'll work through the AI tool you've set up\(named).
        Add a project, then just tell me what you need in your own words.
        """
    }
}

/// The makers written out for a sentence. An empty list still has to read as
/// English, because "Install  and sign in" is how a missing argument would show
/// up on screen — and the reason this file is a tested function at all is that
/// nothing else in the app can see a broken string.
func makerList(_ makers: [String]) -> String {
    switch makers.count {
    case 0: return "an AI coding tool"
    case 1: return makers[0]
    default: return makers.dropLast().joined(separator: ", ") + " or " + makers[makers.count - 1]
    }
}
