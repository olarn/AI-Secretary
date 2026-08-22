import FunctionalCore
import Foundation

public enum BackendReadiness: Equatable, Sendable {
    case looking
    case notInstalled
    case ready(version: Option<String>)
}

public func emptyTranscriptHint(_ readiness: BackendReadiness, makers: [String]) -> String {
    switch readiness {
    case .looking:
        return "Checking for your AI tool…"
    case .notInstalled:
        return "Install \(makerList(makers)) and sign in, and I'll be able to work for you."
    case .ready(let version):
        let named = version.map { " (\($0))" }^.getOrElse("")
        return """
        Ready — I'll work through the AI tool you've set up\(named).
        Add a project, then just tell me what you need in your own words.
        """
    }
}

func makerList(_ makers: [String]) -> String {
    switch makers.count {
    case 0: return "an AI coding tool"
    case 1: return makers[0]
    default: return makers.dropLast().joined(separator: ", ") + " or " + makers[makers.count - 1]
    }
}
