import Foundation

/// The assistant asking the app to pass something to another character.
///
/// ```to
/// Pikachu
/// หาราคา civic 2015 เทียบกับ vios 2015 ให้หน่อย
/// ```
///
/// **This exists because the alternative was a lie.** The app reads the
/// person's own words for a hand-off, and that catches the plain cases — but
/// when it misses, the turn goes to the model, and a model that has just been
/// told other characters exist will try to reach them. Driven on 2026-08-14:
/// Ditto found Claude Code's own `SendMessage`, aimed it at a Claude Code
/// session, and reported success to the person. Nothing had been sent.
///
/// Denying that tool stops the false claim; it does not give her a way to do
/// the thing she was asked to do. This is that way, and it is the same shape as
/// every other request the assistant can make of the app — marked, never
/// inferred, so a reply that merely *mentions* asking Pikachu stays a sentence.
///
/// First line is who, the rest is what. The name is matched against the roster
/// by the caller, which knows who is on the desktop; an unknown name is
/// answered rather than guessed at.
public struct HandOffBlock: Equatable, Sendable {
    public struct Request: Equatable, Sendable {
        /// Everyone named on the first line.
        ///
        /// Plural since 0.14.242. It took one name, so a character asked for
        /// something from two people could only ever reach one — and said so,
        /// out loud, to the person who had asked for both: *"ขอถามทีละคนก่อนค่ะ"*.
        /// She was describing the limit of the block she had been given.
        public let to: [String]
        public let message: String

        public init(to: [String], message: String) {
            self.to = to
            self.message = message
        }
    }

    /// The message with the block taken out, ready to render.
    public let body: String
    public let request: Request?

    static let fence = "```to"

    public init(body: String, request: Request?) {
        self.body = body
        self.request = request
    }

    /// Several names on one line, however they were separated.
    ///
    /// A model writes a list the way a person would — commas, `และ`, `and` —
    /// so all of them are accepted rather than one being mandated and the rest
    /// silently swallowed as part of a name.
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

        // `to: Pikachu` reads better in a prompt than a bare name, so the label
        // is accepted and dropped — the same courtesy `WatchBlock` extends to
        // `path:`.
        let heading = first
            .replacingOccurrences(of: "to:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        let names = splitNames(heading)
        let message = lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // A name with nothing to say is not a request. Sending an empty errand
        // would put "← Ditto passed this on from you" in someone's chat above
        // no question at all.
        guard !names.isEmpty, !message.isEmpty else {
            return HandOffBlock(body: text, request: nil)
        }
        return HandOffBlock(body: body, request: Request(to: names, message: message))
    }
}
