import Foundation

public struct OutstandingRequest: Equatable, Sendable {
    public let request: String
    public let missing: String

    public init(request: String, missing: String) {
        self.request = request
        self.missing = missing
    }

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

public struct BlockedBlock: Equatable, Sendable {
    public let body: String
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

public func isWaitingForPermission(_ missing: String) -> Bool {
    let words = [
        "permission", "approval", "not allowed", "allowlist", "grant",
        "สิทธิ์", "อนุญาต"
    ]
    return words.contains { missing.localizedCaseInsensitiveContains($0) }
}

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
