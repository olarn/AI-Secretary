import Foundation

public enum ActionClass: String, Codable, CaseIterable, Sendable {
    case readOnly
    case localWrite
    case projectMemoryWrite
    case destructive
    case gitHistoryChanging
    case dependencyInstalling
    case externalNetwork
    case browserAction
    case directoryAccess

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
        case .directoryAccess: return "Opens another folder to the assistant"
        }
    }
}
