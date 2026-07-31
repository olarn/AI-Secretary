import Foundation

/// A request the assistant could not finish, and what it was missing.
///
/// Held by the app rather than left to the model to remember. Telling the model
/// "a message that supplies the missing piece belongs to the earlier request"
/// was not enough on its own: asked for a ratebook and told where to look, it
/// treated the second message as a fresh instruction, confirmed the tool worked,
/// and searched for something else. With the request written down, the app can
/// put it back in front of the model on the next turn instead of hoping.
public struct OutstandingRequest: Equatable, Sendable {
    /// The user's words, verbatim.
    public let request: String
    /// What the assistant said it lacked, in its own words.
    public let missing: String

    public init(request: String, missing: String) {
        self.request = request
        self.missing = missing
    }

    /// The line handed to the backend on the next turn. Written as an
    /// instruction about *this* conversation rather than a general rule,
    /// because a general rule is what already failed.
    public var reminder: String {
        """
        UNFINISHED REQUEST. Earlier the user asked: "\(request)". You could not \
        finish it because: \(missing). If the message you are answering now \
        supplies that — a path, a project, a tool, a permission, or simply where \
        to look — then carry out that earlier request in full and answer it, \
        including any part of it asking you to pin or show something separately. \
        Do not merely confirm that the tool works, and do not demonstrate it on \
        different data. If the message is plainly about something else, ignore \
        this note.
        """
    }
}

/// Reading a ` ```blocked ` marker out of a reply.
///
/// Same bargain as the other markers: the app never infers this. "I couldn't
/// find that" appears in ordinary answers constantly, and treating every such
/// sentence as an unfinished request would put a stale reminder in front of the
/// model for the rest of the conversation.
public struct BlockedBlock: Equatable, Sendable {
    /// The message with the marker taken out.
    public let body: String
    /// What the assistant said it was missing, if it declared anything.
    public let missing: String?

    public static let fence = "```blocked"

    public static func parse(_ text: String) -> BlockedBlock {
        guard text.contains(fence) else { return BlockedBlock(body: text, missing: nil) }

        var kept: [String] = []
        var inside = false
        var reason: [String] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inside, trimmed == fence {
                inside = true
                continue
            }
            if inside, trimmed == "```" {
                inside = false
                continue
            }
            if inside {
                reason.append(trimmed)
            } else {
                kept.append(line)
            }
        }

        let missing = reason.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !missing.isEmpty else { return BlockedBlock(body: text, missing: nil) }

        return BlockedBlock(
            body: kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            missing: missing
        )
    }

    public init(body: String, missing: String?) {
        self.body = body
        self.missing = missing
    }
}
