import Foundation

public struct RelayAnswer: Equatable, Sendable {
    public let name: String
    public let body: String

    public init(name: String, body: String) {
        self.name = name
        self.body = body
    }
}

public struct StepwiseRequest: Equatable, Sendable {
    public let first: String
    public let rest: String

    public init(first: String, rest: String) {
        self.first = first
        self.rest = rest
    }
}

private func stepNumber(of line: String) -> Int? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "ข้อ", with: "")
        .trimmingCharacters(in: .whitespaces)
    let digits = trimmed.prefix { $0.isNumber }
    guard !digits.isEmpty, let n = Int(digits) else { return nil }
    let after = trimmed.dropFirst(digits.count).first
    guard after == "." || after == ")" || after == ":" else { return nil }
    return n
}

public func stepwise(_ text: String) -> StepwiseRequest? {
    let lines = text.components(separatedBy: .newlines)
    let starts = lines.enumerated().compactMap { index, line in
        stepNumber(of: line).map { (index: index, number: $0) }
    }
    guard starts.count >= 2, starts[0].number == 1, starts[0].index == 0 else { return nil }

    let secondStart = starts[1].index
    let first = lines[0..<secondStart].joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let rest = lines[secondStart...].joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !first.isEmpty, !rest.isEmpty else { return nil }
    return StepwiseRequest(first: first, rest: rest)
}

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

public func relayFanOutLine(to names: [String]) -> String {
    guard names.count > 1 else { return relaySentLine(to: names.first ?? "") }
    let list = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    return "→ Passed this on to \(list). I'll say when the answers are in."
}

public func relayUnavailableLine(_ names: [String]) -> String {
    let list = names.joined(separator: ", ")
    return "\(list) couldn't be reached, so I'm not waiting on \(names.count == 1 ? "her" : "them")."
}
