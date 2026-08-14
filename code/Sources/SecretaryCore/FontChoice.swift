import Foundation

/// Which face the conversation is set in.
///
/// Four system designs rather than a list of installed families, and the reason
/// is the one that made this setting necessary in the first place. The chat was
/// drawn with `monospacedSystemFont`, which has no Thai glyphs at all, so every
/// Thai word fell out of it into whatever the system reached for next — measured
/// on 2026-08-14, that is Ayuthaya, a wide display face that reads as bold
/// beside the Latin around it. Nothing in the app had ever asked for bold.
///
/// A system design cannot repeat that. Each is a request the font machinery
/// resolves per script, so Thai lands on the Thai face of that design instead of
/// on whatever happens to be installed. A named family can't promise it: half of
/// what `availableFontFamilies` returns has no Thai at all, and offering a
/// picker whose entries turn the owner's own messages into empty boxes would be
/// a worse bug than the one being fixed.
///
/// Code is not affected by any of this. A fenced block stays monospaced whatever
/// is chosen here — alignment is the whole point of it, and this setting is
/// about prose.
public enum FontChoice: String, CaseIterable, Sendable, Codable {
    /// The face the rest of macOS is set in.
    case system
    /// The same proportions with the corners taken off. Softer, and noticeably
    /// friendlier at the sizes a companion window is read at.
    case rounded
    /// With serifs, for reading long answers rather than scanning short ones.
    case serif
    /// Fixed width everywhere, which is what the chat used to be for everyone.
    /// Kept as a choice, not as the default: it is the right face for output
    /// and the wrong one for a conversation.
    case monospaced

    public var label: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Mono"
        }
    }

    /// What the row in Settings says under the name.
    public var explanation: String {
        switch self {
        case .system: return "Matches macOS"
        case .rounded: return "Softer edges"
        case .serif: return "Easier to read at length"
        case .monospaced: return "Fixed width"
        }
    }
}
