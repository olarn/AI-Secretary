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

// MARK: - The one kind of missing nobody can hand over

/// Whether what the assistant marked as missing is a *permission*.
///
/// This is not prose-reading of the kind the charter forbids: the text comes
/// out of a ` ```blocked ` block, a field we defined and asked for, and the
/// question asked of it is only "is this the sort of missing that waiting
/// cannot fix". Nothing is acted on from an unmarked sentence.
///
/// Why it needs answering at all — the deadlock the owner hit on 2026-08-20,
/// commanding four characters into a shared folder whose `CLAUDE.md` opens
/// with *"เมื่อพร้อม ทุกคน จะขอ write permission file และ folder ของ project"*
/// ("when ready, everyone will ask for write permission"). อาเนีย did exactly
/// that: she asked, in words — *"หนูขอสิทธิ์เขียนไฟล์ 2.actions/task.md"* — and
/// then waited. **There is nobody to ask.** Claude Code has no mid-turn
/// approval; in this app the only way to raise the question is to make the
/// call and be refused, and a request that is never made is never refused, so
/// no card is ever drawn and the turn ends with her waiting for ever. The
/// other three attempted, were refused for real, and were widened.
///
/// Both languages, because the character answers in the person's, and the
/// blocked line is written in whatever she was speaking.
public func isWaitingForPermission(_ missing: String) -> Bool {
    let words = [
        "permission", "approval", "not allowed", "allowlist", "grant",
        "สิทธิ์", "อนุญาต"
    ]
    return words.contains { missing.localizedCaseInsensitiveContains($0) }
}

/// What the app says to the assistant to break that deadlock.
///
/// It grants nothing and it cannot: it only tells her that the waiting she has
/// settled into has no end, and that attempting is how the person gets asked.
/// The refusal that follows is real, and *that* is what draws the card.
///
/// Addressed to the project instruction by name, because that is what she is
/// obeying and she is right to obey it — the app has to say how this project
/// asks, not tell her to ignore what she was told.
public func permissionNudge(missing: String) -> String {
    """
    [The app] You said you were blocked, needing: \(missing). Nobody is coming \
    to grant that — there is no way to hand you a permission in words, and a \
    message saying you have it would not change what your tools can do. \
    **Asking, here, means making the call.** Attempt it now. If you are not \
    allowed, the attempt is refused, the app shows the person exactly what was \
    blocked, they allow it in one click, and your request runs again with the \
    tool in hand. That is what a project instruction like "ask for write \
    permission first" means in this app, and it is satisfied by trying, not by \
    waiting. If the attempt is refused, say so in one line and stop — do not \
    ask again in words.
    """
}
