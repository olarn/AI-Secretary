import Foundation

public let inheritedSettingName = "Default"

public func shortModelName(_ displayName: String) -> String {
    let prefix = "Claude "
    guard displayName.hasPrefix(prefix) else { return displayName }
    return String(displayName.dropFirst(prefix.count))
}

public func modelBadge(model: String, effort: String) -> String {
    let short = shortModelName(model)
    guard short != inheritedSettingName || effort != inheritedSettingName else {
        return inheritedSettingName
    }
    return "\(short) | \(effort)"
}
