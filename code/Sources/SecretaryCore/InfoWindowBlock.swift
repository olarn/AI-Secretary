import Foundation

public struct InfoWindowSpec: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, body: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

public struct InfoWindowBlock: Equatable, Sendable {
    public let body: String
    public let requests: [InfoWindowSpec]

    public static let fence = "```window"

    public static func parse(_ text: String, now: Date = Date()) -> InfoWindowBlock {
        guard text.contains(fence) else { return InfoWindowBlock(body: text, requests: []) }

        var kept: [String] = []
        var found: [InfoWindowSpec] = []
        var inside = false
        var title: String?
        var content: [String] = []

        func finishBlock() {
            let body = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                found.append(InfoWindowSpec(title: title ?? Self.defaultTitle, body: body, createdAt: now))
            }
            title = nil
            content = []
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inside, trimmed == fence {
                inside = true
                continue
            }
            if inside, trimmed == "```" {
                inside = false
                finishBlock()
                continue
            }
            if inside {
                if title == nil, let named = Self.title(of: trimmed) {
                    title = named
                } else {
                    content.append(line)
                }
            } else {
                kept.append(line)
            }
        }
        let anUnterminatedBlockStillCountsBecauseTheStreamEndedNotTheIntent = inside
        if anUnterminatedBlockStillCountsBecauseTheStreamEndedNotTheIntent { finishBlock() }

        guard !found.isEmpty else { return InfoWindowBlock(body: text, requests: []) }

        return InfoWindowBlock(
            body: kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            requests: found
        )
    }

    public static let defaultTitle = "Pinned"

    public init(body: String, requests: [InfoWindowSpec]) {
        self.body = body
        self.requests = requests
    }

    private static func title(of line: String) -> String? {
        let lowered = line.lowercased()
        guard lowered.hasPrefix("title:") else { return nil }
        let value = line.dropFirst("title:".count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

public struct InfoWindowSet: Equatable, Sendable {
    public private(set) var windows: [InfoWindowSpec]

    public static let limit = 10

    public static let empty = InfoWindowSet(windows: [])

    public init(windows: [InfoWindowSpec]) {
        self.windows = windows
    }

    public func adding(_ spec: InfoWindowSpec) -> InfoWindowSet {
        var next = windows
        next.append(spec)
        if next.count > Self.limit { next.removeFirst(next.count - Self.limit) }
        return InfoWindowSet(windows: next)
    }

    public func removing(_ id: UUID) -> InfoWindowSet {
        InfoWindowSet(windows: windows.filter { $0.id != id })
    }

    public var cleared: InfoWindowSet { .empty }

    public var isEmpty: Bool { windows.isEmpty }

    public func window(_ id: UUID) -> InfoWindowSpec? {
        windows.first { $0.id == id }
    }

    public func matching(title: String, body: String) -> InfoWindowSpec? {
        windows.first { $0.title == title && $0.body == body }
    }
}
