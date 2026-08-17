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
    /// Send it — to one character, or to several at once.
    ///
    /// Plural since 0.14.236, and still plural, but **prose no longer produces
    /// a plural**: from Sprint 17 the several-recipients case comes from the
    /// model's own ```to block, which names them a line at a time and is read
    /// rather than scanned. Reading "จาก Pikachu และ Ditto" as two recipients
    /// meant asking `contains("และ")` whether a conjunction joined the *names*,
    /// which it cannot know — and the price of being wrong is the person's work
    /// sent to somebody who was never asked.
    case confident(to: [CharacterCard], errand: String)
}

/// Phrases that name a third party by their shape alone — the person is asking
/// for something to be passed on, not asking you.
///
/// These stand on their own: `ขอให้` with nobody named still means somebody
/// else is meant to do it, and that is the case this list exists for.
///
/// **Frozen. Do not add to this list.** It grew twice in one day (2026-08-14)
/// chasing sentences that had slipped through, and the second note recorded
/// that the slipped case reached the model and *did the right thing through the
/// block*. That is the answer: a phrasing this list misses is the model's to
/// read, not a signal to type another keyword. Substring matching on a language
/// written without spaces cannot be made good by lengthening it, and every
/// word added widened what it caught in ordinary sentences too.
let handOffPhrases = [
    "ขอให้", "ฝากถาม", "ฝากบอก", "ฝากให้", "ช่วยถาม", "ช่วยบอก", "บอกให้",
    "ask ", "tell ", "forward", "pass this", "pass it",
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
    guard contains(handOffPhrases, errand) else { return .none }

    switch named.count {
    // One unambiguous hand-off phrase, one name on it. The only reading this
    // function still makes on its own.
    case 1:
        return .confident(to: named, errand: errand)
    // Several names is always a question now. It used to send to all of them
    // when a conjunction appeared somewhere in the sentence, which was a guess:
    // `contains("กับ")` cannot tell "Anya กับ Ditto" from "Anya กับผม", and a
    // wrong recipient is work sent to someone who was never asked, with no
    // undo. A person who means both is one tap away through the question, and
    // the model — which reads the sentence rather than scanning it — names both
    // in its own block when it is sure.
    case 2...:
        return .unsure(candidates: named, errand: errand)
    // The case this whole enum exists for. The owner's own scenario writes
    // "อาเนีย" for a character whose profile name is "Anya", so a roster-name
    // match finds nothing and the message would otherwise be answered as if it
    // had been meant for the character it was typed at — which reads, correctly,
    // as the feature not working. A phrase that means "somebody else" with
    // nobody matched asks who.
    default:
        return .unsure(candidates: directory, errand: errand)
    }
}

/// Offered alongside the names, because the reading may simply be wrong.
///
/// Without a way out, a false positive on `ขอให้` — which appears in ordinary
/// sentences that have nothing to do with anyone else — would leave the person
/// with no option but to send work somewhere they never meant to.
public let answerItYourselfChoice = "No — answer it yourself"

/// Offered whenever more than one name was found, so that "both of them" is a
/// tap rather than a rephrase.
///
/// Sprint 17 stopped prose from producing several recipients on its own, since
/// deciding it meant asking `contains("และ")` whether a conjunction joined the
/// *names*. Asking instead is right; asking a question whose only answers are
/// "Anya" and "Ditto" when the person plainly wrote both is not — that is the
/// app making them choose one, which is the same wrong guess with an extra
/// step. So the question carries the answer they meant.
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
