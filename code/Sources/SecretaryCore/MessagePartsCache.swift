import Foundation

public final class MessagePartsCache {
    private var remembered: [UUID: (text: String, parts: [MessagePart])] = [:]

    public private(set) var hits = 0
    public private(set) var misses = 0

    public init() {}

    public func parts(id: UUID, text: String) -> [MessagePart] {
        if let hit = remembered[id], hit.text == text {
            hits += 1
            return hit.parts
        }
        misses += 1
        let parsed = messageParts(of: DelimitedTableParser.segments(of: displayBody(of: text)))
        remembered[id] = (text, parsed)
        return parsed
    }

    public func keepingOnly(_ ids: Set<UUID>) {
        remembered = remembered.filter { ids.contains($0.key) }
    }
}

public func displayBody(of text: String) -> String {
    LoopBlock.parse(MessageChoices.parse(text).body).body
}
