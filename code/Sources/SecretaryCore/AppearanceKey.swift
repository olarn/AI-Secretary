import Foundation

/// Where one character's look is kept in `UserDefaults`.
///
/// A free function rather than string building inside the store, because the
/// two things that must not drift are on either side of a launch: what `save`
/// writes and what `load` reads, including the app-wide name a character falls
/// back to before she has been changed. Getting them out of step is silent —
/// the settings simply stop being remembered.
public func appearanceKey(_ setting: String, character: UUID?) -> String {
    guard let character else { return "appearance.\(setting)" }
    return "appearance.\(character.uuidString).\(setting)"
}
