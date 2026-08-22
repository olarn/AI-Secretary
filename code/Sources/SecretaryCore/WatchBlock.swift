import Foundation

public struct WatchBlock: Equatable, Sendable {
    public enum Request: Equatable, Sendable {
        case start(path: String)
        case stop(path: String?)
    }

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

        let words = first.split(separator: " ", maxSplits: 1).map(String.init)
        if let head = words.first, LoopCommand.stopWords.contains(head.lowercased()) {
            let named = words.count > 1 ? words[1].trimmingCharacters(in: .whitespaces) : ""
            return WatchBlock(body: body, request: .stop(path: named.isEmpty ? nil : named))
        }

        let path = droppingTheLabelThatReadsBetterInAPrompt("path:", from: first)
        guard !path.isEmpty else { return WatchBlock(body: text, request: nil) }
        return WatchBlock(body: body, request: .start(path: path))
    }
}

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
