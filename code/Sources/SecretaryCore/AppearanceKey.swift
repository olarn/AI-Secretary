import Foundation

public func appearanceKey(_ setting: String, character: UUID?) -> String {
    guard let character else { return "appearance.\(setting)" }
    return "appearance.\(character.uuidString).\(setting)"
}
