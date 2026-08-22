import FunctionalCore
import Foundation

public struct SaveFileBlock: Equatable, Sendable {
    public let body: String
    public let names: [String]

    static let fence = "```save-file"

    static let limit = 5

    public init(body: String, names: [String]) {
        self.body = body
        self.names = names
    }

    public static func parse(_ text: String) -> SaveFileBlock {
        guard text.contains(fence) else { return SaveFileBlock(body: text, names: []) }

        var body: [String] = []
        var block: [String] = []
        var insideBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !insideBlock, trimmed == fence {
                insideBlock = true
                continue
            }
            if insideBlock {
                if trimmed.hasPrefix("```") {
                    insideBlock = false
                    continue
                }
                block.append(trimmed)
                continue
            }
            body.append(line)
        }

        return SaveFileBlock(
            body: body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            names: Array(block.filter { !$0.isEmpty }.prefix(limit))
        )
    }
}

public struct OfferedFile: Equatable, Sendable, Identifiable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
    public let byteCount: Int

    public init(name: String, url: URL, byteCount: Int) {
        self.name = name
        self.url = url
        self.byteCount = byteCount
    }
}

public enum SaveOfferError: Error, Equatable, Sendable {
    case empty
    case notInsideScratch(name: String)
    case missing(name: String)
}

public func offeredFile(
    named raw: String,
    inScratch root: URL,
    resolveSymlinks: (URL) -> URL = { $0.resolvingSymlinksInPath() },
    size: (URL) -> Int? = { url in
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    }
) -> Either<SaveOfferError, OfferedFile> {
    let name = raw.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return .left(.empty) }
    guard !name.hasPrefix("/"), !name.hasPrefix("~") else {
        return .left(.notInsideScratch(name: name))
    }

    let candidate = resolveSymlinks(root.appendingPathComponent(name).standardized)
    let base = resolveSymlinks(root.standardized)
    guard candidate.path.hasPrefix(base.path + "/") else {
        return .left(.notInsideScratch(name: name))
    }

    return Option.fromOptional(size(candidate))
        .fold(
            { .left(.missing(name: name)) },
            {
                .right(
                    OfferedFile(
                        name: candidate.lastPathComponent,
                        url: candidate,
                        byteCount: $0
                    )
                )
            }
        )
}

public func offeredFiles(
    named raws: [String],
    inScratch root: URL,
    resolveSymlinks: (URL) -> URL = { $0.resolvingSymlinksInPath() },
    size: (URL) -> Int? = { url in
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    }
) -> [OfferedFile] {
    raws
        .map { offeredFile(named: $0, inScratch: root, resolveSymlinks: resolveSymlinks, size: size) }
        .compactMap { $0.fold({ _ -> OfferedFile? in nil }, { $0 }) }
}
