import Foundation

/// What the person's message looks like it wants doing about another character.
///
/// Three answers rather than two, and the middle one is the point. The charter
/// forbids guessing an action out of prose — the ```choices block exists
/// because a model writes lists constantly and picking them up built pickers
/// over things that were never questions. The rule that survives is not "never
/// read prose", it is **never act silently on a guess**: an unsure reading here
/// becomes a question the person answers, so nothing is done on a maybe.
public enum DelegationReading: Equatable, Sendable {
    /// Nothing about anyone else. An ordinary turn.
    case none
    /// Someone is meant to be asked and it isn't clear who.
    case unsure(candidates: [CharacterCard], errand: String)
    case confident(to: CharacterCard, errand: String)
}

/// Phrases that name a third party by their shape alone — the person is asking
/// for something to be passed on, not asking you.
///
/// These stand on their own: `ขอให้` with nobody named still means somebody
/// else is meant to do it, and that is the case that makes this list worth
/// keeping separate from the one below.
let handOffPhrases = [
    "ขอให้", "ฝากถาม", "ฝากบอก", "ฝากให้", "ช่วยถาม", "ช่วยบอก", "บอกให้",
    "ask ", "tell ", "forward", "pass this", "pass it",
]

/// Weaker verbs. On their own these are ordinary words — `ให้` is a fragment of
/// half the polite sentences in Thai, and "send" is usually about a file — so
/// they never reach a confident reading. With a name beside them they are worth
/// a question, and no more than a question.
let addressPhrases = [
    "ถาม", "บอก", "ส่งให้", "ส่งไปให้", "แจ้ง",
    "check with", "message", "send", "have ", "get ",
]

/// A name short enough to appear inside ordinary words is not looked for.
///
/// Thai runs without spaces, so matching has to be by substring, and a
/// one-character name would match nearly every sentence. Two is the shortest
/// that is worth trusting; a character called "A" simply cannot be addressed by
/// name, which is a better failure than every message being read as an errand.
let shortestMatchableName = 2

/// A *first word* has to clear a higher bar than a whole name, because it is a
/// guess about what somebody is called rather than what they are called.
/// Three was not enough: "The Assistant" offered "the", which appears in most
/// English sentences ever typed. "Miku" is four.
let shortestMatchableFirstWord = 4

/// The ways a character can be named in a sentence.
///
/// Her whole profile name, and — when it is several words — the first of them.
/// Profiles carry what they are for as well as who they are: the one on this
/// machine is called **Miku (Second Brain)**, and nobody types that. Without the
/// first word she could not be addressed at all, which would have shipped as
/// "it works for one of my characters and not the other".
///
/// Only the first word, and only when it is long enough to be worth trusting:
/// "The" and "Dr" would match half of everything.
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

/// Reads the person's own words against the roster.
///
/// Deterministic: no clock, no ids minted, same text and same roster in, same
/// answer out. The errand it hands on is **the whole message, uncut**. Trying
/// to excise "ช่วยขอให้อาเนีย" and forward only the remainder is exactly the kind
/// of surgery that goes wrong on a language without spaces, and the recipient
/// reads the request better with the sentence intact than with a stump of it.
public func delegationIntent(in text: String, directory: [CharacterCard]) -> DelegationReading {
    let errand = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !errand.isEmpty, !directory.isEmpty else { return .none }

    let named = mentioned(directory, in: errand)
    let handOff = contains(handOffPhrases, errand)
    let addressed = handOff || contains(addressPhrases, errand)

    // Only an unambiguous hand-off phrase with exactly one name on it is acted
    // on without asking. Everything else that looks like it might involve
    // someone else becomes a question — a wrong guess here sends the person's
    // work to a character they never named, and there is no undo for that.
    switch (named.count, handOff, addressed) {
    case (1, true, _):
        return .confident(to: named[0], errand: errand)
    // Two names and a verb: which of them is a coin toss.
    case (2..., _, true):
        return .unsure(candidates: named, errand: errand)
    // A name and a weaker verb — "อาเนียบอกว่าอะไรนะ" is a question *about* her,
    // not a request to send her anything, and the two are not separable by
    // wording. Ask.
    case (1, false, true):
        return .unsure(candidates: named, errand: errand)
    // The case this whole enum exists for. The owner's own scenario writes
    // "อาเนีย" for a character whose profile name is "Anya", so a roster-name
    // match would find nothing and the message would be answered as if it had
    // been meant for the character it was typed at — which reads, correctly, as
    // the feature not working. A phrase that means "somebody else" with nobody
    // matched asks who.
    case (0, true, _):
        return .unsure(candidates: directory, errand: errand)
    default:
        return .none
    }
}

/// Offered alongside the names, because the reading may simply be wrong.
///
/// Without a way out, a false positive on `ขอให้` — which appears in ordinary
/// sentences that have nothing to do with anyone else — would leave the person
/// with no option but to send work somewhere they never meant to.
public let answerItYourselfChoice = "No — answer it yourself"

public func delegationQuestion(_ candidates: [CharacterCard]) -> String {
    candidates.count == 1
        ? "Should I pass this to \(candidates[0].name)?"
        : "Who should take this?"
}

public func delegationChoices(_ candidates: [CharacterCard]) -> [String] {
    candidates.map(\.name) + [answerItYourselfChoice]
}
