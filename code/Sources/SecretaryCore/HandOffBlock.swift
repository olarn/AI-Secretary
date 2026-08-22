import Foundation

public struct HandOffBlock: Equatable, Sendable {
    public struct Request: Equatable, Sendable {
        public let to: [String]
        public let message: String

        public init(to: [String], message: String) {
            self.to = to
            self.message = message
        }
    }

    public let body: String
    public let request: Request?

    static let fence = "```to"

    public init(body: String, request: Request?) {
        self.body = body
        self.request = request
    }

    static func splitNames(_ heading: String) -> [String] {
        var working = heading
        for separator in [",", " และ ", "และ", " กับ ", "กับ", " and ", "&", "+", ";"] {
            working = working.replacingOccurrences(of: separator, with: "\u{1}")
        }
        return working.components(separatedBy: "\u{1}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func parse(_ text: String) -> HandOffBlock {
        guard let (body, lines) = FencedBlock.split(text, fence: fence),
              let first = lines.first
        else { return HandOffBlock(body: text, request: nil) }

        let heading = droppingTheLabelThatReadsBetterInAPrompt("to:", from: first)
        let names = splitNames(heading)
        let message = lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let aNameWithNothingToSayIsNotARequest = names.isEmpty || message.isEmpty
        guard !aNameWithNothingToSayIsNotARequest else {
            return HandOffBlock(body: text, request: nil)
        }
        return HandOffBlock(body: body, request: Request(to: names, message: message))
    }
}
