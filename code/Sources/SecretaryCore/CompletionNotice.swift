import Foundation

public struct FinishedTurn: Equatable, Sendable {
    public let characterName: String
    public let text: String
    public let succeeded: Bool
    public let wasErrand: Bool
    public let choices: [String]

    public init(
        characterName: String,
        text: String,
        succeeded: Bool,
        wasErrand: Bool,
        choices: [String] = []
    ) {
        self.characterName = characterName
        self.text = text
        self.succeeded = succeeded
        self.wasErrand = wasErrand
        self.choices = choices
    }
}

public struct CompletionNotice: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public func completionNotice(
    for turn: FinishedTurn,
    isChatVisible: Bool
) -> CompletionNotice? {
    guard !turn.wasErrand else { return nil }
    guard !isChatVisible else { return nil }

    let body = noticeBody(turn.text)
    guard !body.isEmpty else { return nil }

    return CompletionNotice(
        title: turn.succeeded ? turn.characterName : "\(turn.characterName) couldn't finish",
        body: body
    )
}

public func noticeBody(_ text: String, limit: Int = 180) -> String {
    let flattened = text
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    guard flattened.count > limit else { return flattened }
    return flattened.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
}
