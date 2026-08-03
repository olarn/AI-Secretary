/// The name above a message in the transcript.
///
/// Two rules, and both of them are the kind that quietly rot if they live in a
/// view: the user is always "Me" whatever profile is active, and the assistant
/// is whoever it was *when the line was written* — see `TranscriptEntry
/// .speakerName` for why that is stored rather than looked up.
///
/// - Parameters:
///   - isMine: whether this is the user's own turn.
///   - speakerName: the name recorded on the entry. Blank for entries written
///     before names were recorded, and for anything that somehow reaches here
///     without one; those fall back rather than rendering an anonymous line.
public func speakerLabel(isMine: Bool, speakerName: String) -> String {
    if isMine { return "Me" }
    let trimmed = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Secretary" : trimmed
}
