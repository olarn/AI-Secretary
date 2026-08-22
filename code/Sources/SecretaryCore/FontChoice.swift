import Foundation

public enum FontChoice: String, CaseIterable, Sendable, Codable {
    case system
    case rounded
    case serif
    case monospaced

    public var label: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Mono"
        }
    }

    public var explanation: String {
        switch self {
        case .system: return "Matches macOS"
        case .rounded: return "Softer edges"
        case .serif: return "Easier to read at length"
        case .monospaced: return "Fixed width"
        }
    }
}
