import Foundation

/// The assistant asking the app to watch a path, or to stop watching.
///
/// Without this the feature only half worked. Asked to "คอย monitor folder aaa
/// แล้วบอกชื่อไฟล์ที่เพิ่มมา" the assistant understood the request perfectly
/// and then told the person to type `/watch .` themselves — the one thing a
/// secretary shouldn't do with an instruction it already understood.
///
/// ```watch
/// aaa
/// ```
///
/// Marked rather than inferred, for the reason every other block here is: a
/// reply that merely mentions keeping an eye on something must not start a
/// background job. What the marker buys is that the request is unmistakable;
/// what keeps it safe is unchanged — the path is resolved inside an approved
/// project, the first watch in a project still meets the permission card, the
/// start is announced, and the badge stops it in one click.
public struct WatchBlock: Equatable, Sendable {
    public enum Request: Equatable, Sendable {
        case start(path: String)
        case stop
    }

    /// The message with the block taken out, ready to render.
    public let body: String
    public let request: Request?

    static let fence = "```watch"

    public init(body: String, request: Request?) {
        self.body = body
        self.request = request
    }

    public static func parse(_ text: String) -> WatchBlock {
        guard let (body, lines) = FencedBlock.split(text, fence: fence), let first = lines.first else {
            return WatchBlock(body: text, request: nil)
        }

        if LoopCommand.stopWords.contains(first.lowercased()) {
            return WatchBlock(body: body, request: .stop)
        }

        // `path: docs` reads better in a prompt than a bare `docs`, so the
        // label is accepted and dropped.
        let path = first
            .replacingOccurrences(of: "path:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return WatchBlock(body: text, request: nil) }
        return WatchBlock(body: body, request: .start(path: path))
    }
}

/// The assistant asking the app to follow a file's instructions.
///
/// Safe to let the assistant raise because raising it isn't doing it: this only
/// gets as far as reading the file and putting the steps on the confirmation
/// card, which is the same gate a typed `/run` reaches. Nothing runs until the
/// person reads the steps and presses Start.
///
/// ```run
/// deploy.md
/// ```
public struct RunBlock: Equatable, Sendable {
    public enum Request: Equatable, Sendable {
        case start(path: String)
        case stop
    }

    public let body: String
    public let request: Request?

    static let fence = "```run"

    public init(body: String, request: Request?) {
        self.body = body
        self.request = request
    }

    public static func parse(_ text: String) -> RunBlock {
        guard let (body, lines) = FencedBlock.split(text, fence: fence), let first = lines.first else {
            return RunBlock(body: text, request: nil)
        }

        if LoopCommand.stopWords.contains(first.lowercased()) {
            return RunBlock(body: body, request: .stop)
        }

        let path = first
            .replacingOccurrences(of: "file:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return RunBlock(body: text, request: nil) }
        return RunBlock(body: body, request: .start(path: path))
    }
}
