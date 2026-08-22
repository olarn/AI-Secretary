import Foundation

public enum DelegationReading: Equatable, Sendable {
    case none
    case unsure(candidates: [CharacterCard], errand: String)
    case confident(to: [CharacterCard], errand: String)
}

let handOffPhrases = [
    "ขอให้", "ฝากถาม", "ฝากบอก", "ฝากให้", "ช่วยถาม", "ช่วยบอก", "บอกให้",
    "ask ", "tell ", "forward", "pass this", "pass it",
]

let shortestMatchableName = 2

let shortestMatchableFirstWord = 4

func namesFor(_ card: CharacterCard) -> [String] {
    let full = card.name.trimmingCharacters(in: .whitespaces).lowercased()
    let first = full.split(separator: " ").first.map(String.init) ?? full
    let extras = first != full && first.count >= shortestMatchableFirstWord ? [first] : []
    return ([full] + extras).filter { $0.count >= shortestMatchableName }
}

private func mentioned(_ directory: [CharacterCard], in text: String) -> [CharacterCard] {
    let haystack = text.lowercased()
    return directory.filter { card in
        namesFor(card).contains { haystack.contains($0) }
    }
}

private func contains(_ phrases: [String], _ text: String) -> Bool {
    let haystack = text.lowercased()
    return phrases.contains { haystack.contains($0) }
}

public func delegationIntent(in text: String, directory: [CharacterCard]) -> DelegationReading {
    let errand = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !errand.isEmpty, !directory.isEmpty else { return .none }

    let named = mentioned(directory, in: errand)
    guard contains(handOffPhrases, errand) else { return .none }

    switch named.count {
    case 1:
        return .confident(to: named, errand: errand)
    case 2...:
        return .unsure(candidates: named, errand: errand)
    default:
        return .unsure(candidates: directory, errand: errand)
    }
}

public let answerItYourselfChoice = "No — answer it yourself"

public let everyoneChoice = "Both — ask all of them"

public func delegationQuestion(_ candidates: [CharacterCard]) -> String {
    candidates.count == 1
        ? "Should I pass this to \(candidates[0].name)?"
        : "Who should take this?"
}

public func delegationChoices(_ candidates: [CharacterCard]) -> [String] {
    let everyone = candidates.count > 1 ? [everyoneChoice] : []
    return candidates.map(\.name) + everyone + [answerItYourselfChoice]
}
