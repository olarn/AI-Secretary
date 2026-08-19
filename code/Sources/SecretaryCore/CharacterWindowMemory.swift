import CoreGraphics
import Foundation

/// Where each character was left, remembered across launches (20.1).
///
/// The command window already remembers itself; this is the characters' half.
/// Plain Swift for the same reason as `CommandWindow.swift`: it crosses into
/// the app target.

/// One key per character, built in one place so save and load can't drift —
/// the same rule as `appearanceKey`.
public func characterOriginKey(_ character: UUID) -> String {
    "character.\(character.uuidString).origin"
}

/// The remembered origin, if it is still worth using.
///
/// `nil` — meaning "use the default launch position" — when nothing was saved,
/// the save doesn't parse, or the character would come back somewhere she
/// cannot be clicked. The owner's rule is explicit about that last case: a
/// position saved on a screen that is gone (a shared or external display) is
/// *not* clamped back to the nearest edge the way the command window's is —
/// she returns to her default spot, because an edge-clamped character reads as
/// "she moved by herself" while the default reads as a fresh start.
///
/// "On screen" is at least `minimumVisible` of her in both axes inside the
/// whole screen frame, not the visible frame — standing on the Dock is a
/// normal place for a desktop character (the same reasoning as
/// `keepCharacterOnScreen`).
public func savedCharacterOrigin(
    saved: String?,
    size: CGSize,
    screenFrame: CGRect,
    minimumVisible: Double = 24
) -> CGPoint? {
    let parsed = saved
        .map { $0.split(separator: ",").compactMap { Double($0) } }
        .flatMap { parts in parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil }
    guard let origin = parsed else { return nil }

    let frame = CGRect(origin: origin, size: size)
    let visible = frame.intersection(screenFrame)
    guard visible.width >= minimumVisible, visible.height >= minimumVisible else { return nil }
    return origin
}

/// The saved origin, in the only form `UserDefaults` round-trips exactly —
/// the command window's encoding, shared on purpose.
public func characterOriginString(_ origin: CGPoint) -> String {
    commandWindowOriginString(origin)
}
