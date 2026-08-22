import Foundation

public let defaultNewCharacterName = "Secretary"

public func newCharacterDraft(
    from template: SecretaryProfile,
    existing: [SecretaryProfile],
    id: UUID = UUID()
) -> SecretaryProfile {
    SecretaryProfile(
        id: id,
        name: unusedCharacterName(basedOn: template.displayName, existing: existing),
        age: template.age,
        gender: template.gender,
        personality: template.personality
    )
}

public func unusedCharacterName(basedOn name: String, existing: [SecretaryProfile]) -> String {
    let taken = Set(existing.map(\.displayName))
    let stem = characterNameStem(name)
    guard taken.contains(stem) else { return stem }

    let candidates = (2...(taken.count + 2)).lazy.map { "\(stem) \($0)" }
    return candidates.first { !taken.contains($0) } ?? "\(stem) \(taken.count + 2)"
}

private func characterNameStem(_ name: String) -> String {
    let parts = name.split(separator: " ")
    guard parts.count > 1, let last = parts.last, Int(last) != nil else { return name }
    return parts.dropLast().joined(separator: " ")
}
