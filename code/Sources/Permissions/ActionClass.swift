import Foundation

/// Impact classes for anything the assistant can do. Separating these is what
/// lets read-only work proceed cheaply while everything with side effects
/// stops for explicit human approval.
public enum ActionClass: String, Codable, CaseIterable, Sendable {
    case readOnly
    case localWrite
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

    /// Whether this class may ever run without asking, once the working
    /// directory itself has been approved.
    public var canRunUnattended: Bool {
        switch self {
        case .readOnly:
            return true
        case .localWrite, .destructive, .gitHistoryChanging,
             .dependencyInstalling, .externalNetwork, .browserAction:
            return false
        }
    }

    public var humanDescription: String {
        switch self {
        case .readOnly: return "Read-only"
        case .localWrite: return "Writes files in the project"
        case .destructive: return "Deletes or overwrites data"
        case .gitHistoryChanging: return "Changes Git history"
        case .dependencyInstalling: return "Installs software or dependencies"
        case .externalNetwork: return "Sends data to an external service"
        case .browserAction: return "Acts in your browser, as you"
        }
    }
}
