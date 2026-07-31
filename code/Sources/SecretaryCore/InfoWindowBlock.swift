import Foundation

/// A pane of content the assistant was asked to put somewhere it will stay.
public struct InfoWindowSpec: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    /// Markdown, rendered with the same parser the chat uses, so a table asked
    /// for in the chat looks the same once it is pulled out of it.
    public let body: String
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, body: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

/// Reading a ` ```window ` block out of a reply.
///
/// Marker-based for the same reason as ` ```choices ` and ` ```loop `: the model
/// produces tables and lists constantly, and guessing which of them the user
/// wanted kept would open windows nobody asked for. Only an explicit block
/// counts, and the block never survives into what is shown — otherwise the
/// content appears twice, once in the chat and once in the window.
public struct InfoWindowBlock: Equatable, Sendable {
    /// The message with the block taken out.
    public let body: String
    /// What to open, if anything.
    public let request: InfoWindowSpec?

    public static let fence = "```window"

    public static func parse(_ text: String, now: Date = Date()) -> InfoWindowBlock {
        guard text.contains(fence) else { return InfoWindowBlock(body: text, request: nil) }

        var kept: [String] = []
        var inside = false
        var title: String?
        var content: [String] = []

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
                // The first `title:` line names the window; everything after it
                // is content, including any later line that happens to start
                // with "title:".
                if title == nil, let named = Self.title(of: trimmed) {
                    title = named
                } else {
                    content.append(line)
                }
            } else {
                kept.append(line)
            }
        }

        let text2 = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // A block with no content opens nothing, and the message is left whole
        // rather than half-swallowed.
        guard !text2.isEmpty else { return InfoWindowBlock(body: text, request: nil) }

        return InfoWindowBlock(
            body: kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            request: InfoWindowSpec(
                title: title ?? Self.defaultTitle,
                body: text2,
                createdAt: now
            )
        )
    }

    public static let defaultTitle = "Pinned"

    private static func title(of line: String) -> String? {
        let lowered = line.lowercased()
        guard lowered.hasPrefix("title:") else { return nil }
        let value = line.dropFirst("title:".count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

/// The set of panes currently kept open, oldest first.
///
/// A value rather than a mutable list so the menu, the windows and the tests all
/// read the same thing, and so "remove one" and "clear all" are single
/// expressions instead of index arithmetic.
public struct InfoWindowSet: Equatable, Sendable {
    public private(set) var windows: [InfoWindowSpec]

    /// Enough to be useful, few enough that a runaway loop of window blocks
    /// cannot bury the screen. The oldest goes when the limit is reached.
    public static let limit = 12

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
}
