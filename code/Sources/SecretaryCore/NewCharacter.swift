import Foundation

/// What `New Character…` produces.
///
/// Two decisions, and both are the kind the charter says must not live in the
/// view layer: what a new character inherits, and what she is called. A name
/// picked in the app target is a name no test has ever seen.

/// A new character cloned from an existing one, named so she is not confusable
/// with anybody already on the desktop.
///
/// The backlog asks for "configuration from the existing Profile", so
/// everything about who she is comes across — age, gender, personality — and
/// only the identity is new. Her picture does not: artwork is stored per
/// profile id and copying the file would leave two characters that are
/// indistinguishable on screen, which defeats the point of having two.
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

/// "Miku" → "Miku 2" → "Miku 3", skipping any number already taken.
///
/// Names are how the person tells characters apart in the menu and in the
/// transcript, so two called the same thing is not a cosmetic problem: the menu
/// would show two identical rows and neither would say which is which.
///
/// The suffix is stripped before counting, so cloning "Miku 2" gives "Miku 3"
/// rather than "Miku 2 2".
public func unusedCharacterName(basedOn name: String, existing: [SecretaryProfile]) -> String {
    let taken = Set(existing.map(\.displayName))
    let stem = characterNameStem(name)
    guard taken.contains(stem) else { return stem }

    // Bounded by the number of names in play plus one, so there is always an
    // unused candidate in range and the search cannot fail to terminate.
    let candidates = (2...(taken.count + 2)).lazy.map { "\(stem) \($0)" }
    return candidates.first { !taken.contains($0) } ?? "\(stem) \(taken.count + 2)"
}

/// The name without a trailing copy number.
private func characterNameStem(_ name: String) -> String {
    let parts = name.split(separator: " ")
    guard parts.count > 1, let last = parts.last, Int(last) != nil else { return name }
    return parts.dropLast().joined(separator: " ")
}
