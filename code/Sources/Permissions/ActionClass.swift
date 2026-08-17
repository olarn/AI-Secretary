import Foundation

/// Impact classes for anything the assistant can do. Separating these is what
/// lets read-only work proceed cheaply while everything with side effects
/// stops for explicit human approval.
public enum ActionClass: String, Codable, CaseIterable, Sendable {
    case readOnly
    case localWrite
    /// Writes into the project's Claude Code memory directory.
    ///
    /// Split out of `localWrite` so that class means one thing — the assistant
    /// writing inside a folder the person registered — and can therefore be
    /// remembered per project. This one cannot: it writes *outside* every
    /// registered project, into the directory the person's own terminal
    /// `claude` reads back, so "yes" here is a different promise from "yes, work
    /// in my project" and must be asked each time.
    case projectMemoryWrite
    case destructive
    case gitHistoryChanging
    case dependencyInstalling
    case externalNetwork
    /// Acts inside the browser the person is signed into: scrolling, clicking,
    /// typing, opening pages.
    ///
    /// Its own class because the existing ones describe it wrongly, and the
    /// card is where someone decides. Called `localWrite` it read "Writes files
    /// in the project", which is not what a click on a web page does; called
    /// `externalNetwork` it would read as sending data out, which is not it
    /// either. What matters is whose session it acts in — theirs.
    case browserAction

    public var humanDescription: String {
        switch self {
        case .readOnly: return "Read-only"
        case .localWrite: return "Writes files in the project"
        case .projectMemoryWrite: return "Writes to your Claude Code memory, outside the project"
        case .destructive: return "Deletes or overwrites data"
        case .gitHistoryChanging: return "Changes Git history"
        case .dependencyInstalling: return "Installs software or dependencies"
        case .externalNetwork: return "Sends data to an external service"
        case .browserAction: return "Acts in your browser, as you"
        }
    }
}
