public func speakerLabel(isMine: Bool, speakerName: String) -> String {
    if isMine { return "Me" }
    let trimmed = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Secretary" : trimmed
}
