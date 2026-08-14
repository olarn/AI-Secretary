import Foundation

/// One character's answer to an errand.
public struct RelayAnswer: Equatable, Sendable {
    public let name: String
    public let body: String

    public init(name: String, body: String) {
        self.name = name
        self.body = body
    }
}

/// A numbered request split into the part to send now and the part to do once
/// the answers are back.
///
/// The person writes what they want as a list, and the list is the plan:
///
///     1. ขอข้อมูล … จาก Pikachu และ Ditto
///     2. เมื่อได้ข้อมูลทั้ง 2 ชุด ให้รวมข้อมูล แล้วบันทึกลง file ใน project
///
/// Before this, the whole thing was forwarded verbatim and step 2 went with it
/// — so the character who was meant to *do* step 2 never saw it, and the
/// characters who were only meant to answer step 1 were handed an instruction
/// to write files in a project they cannot reach.
public struct StepwiseRequest: Equatable, Sendable {
    /// What to send now.
    public let first: String
    /// What the sender does once the answers are in.
    public let rest: String

    public init(first: String, rest: String) {
        self.first = first
        self.rest = rest
    }
}

/// A line that opens a numbered step: `1.`, `2)`, `ข้อ 3`.
private func stepNumber(of line: String) -> Int? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "ข้อ", with: "")
        .trimmingCharacters(in: .whitespaces)
    let digits = trimmed.prefix { $0.isNumber }
    guard !digits.isEmpty, let n = Int(digits) else { return nil }
    let after = trimmed.dropFirst(digits.count).first
    // A bare "2015 Civic" is a year, not a step. The punctuation is what makes
    // it a list item.
    guard after == "." || after == ")" || after == ":" else { return nil }
    return n
}

/// Splits a numbered request, or `nil` when it is just a message.
///
/// Two steps at minimum, and they have to be numbered — inferring a plan from
/// prose would turn "I want two things: a and b" into a hand-off with a
/// follow-up nobody asked for.
public func stepwise(_ text: String) -> StepwiseRequest? {
    let lines = text.components(separatedBy: .newlines)
    let starts = lines.enumerated().compactMap { index, line in
        stepNumber(of: line).map { (index: index, number: $0) }
    }
    // The first has to be step 1 and there has to be a second one, or this is
    // an ordinary message that happens to contain a numeral.
    guard starts.count >= 2, starts[0].number == 1, starts[0].index == 0 else { return nil }

    let secondStart = starts[1].index
    let first = lines[0..<secondStart].joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let rest = lines[secondStart...].joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !first.isEmpty, !rest.isEmpty else { return nil }
    return StepwiseRequest(first: first, rest: rest)
}

/// What the sender is asked once the answers are in.
///
/// The answers are quoted rather than summarised, and whoever did not answer is
/// named. A follow-up that silently works from one reply when two were asked
/// for produces a comparison of one thing, presented as a comparison of two.
public func followUpPrompt(
    answers: [RelayAnswer],
    missing: [String],
    thenDo: String
) -> String {
    let quoted = answers.map { "From \($0.name):\n\($0.body)" }.joined(separator: "\n\n")
    let absent = missing.isEmpty ? "" : """


        \(missing.joined(separator: " and ")) did not answer in time, so \
        there is nothing from \(missing.count == 1 ? "her" : "them"). Work with \
        what you have and say plainly, in your reply, whose answer is missing — \
        don't present a comparison of one thing as though it were a comparison \
        of \(answers.count + missing.count).
        """
    return """
        The answers you asked for are in.

        \(quoted)\(absent)

        Now do the part you were asked to do once they arrived:

        \(thenDo)
        """
}

/// In the sender's chat, when one errand went to several people.
public func relayFanOutLine(to names: [String]) -> String {
    guard names.count > 1 else { return relaySentLine(to: names.first ?? "") }
    let list = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    return "→ Passed this on to \(list). I'll say when the answers are in."
}

/// Said when somebody could not be sent to at all, so the person knows the
/// plan shrank before it started rather than wondering later.
public func relayUnavailableLine(_ names: [String]) -> String {
    let list = names.joined(separator: ", ")
    return "\(list) couldn't be reached, so I'm not waiting on \(names.count == 1 ? "her" : "them")."
}
