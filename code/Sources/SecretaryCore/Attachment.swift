import FunctionalCore
import Foundation

public struct Attachment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let stagedURL: URL
    public let kind: AttachmentKind

    public init(id: UUID = UUID(), name: String, stagedURL: URL, kind: AttachmentKind) {
        self.id = id
        self.name = name
        self.stagedURL = stagedURL
        self.kind = kind
    }
}

public enum AttachmentKind: String, Equatable, Sendable, CaseIterable {
    case markdown
    case csv
    case json
    case text
    case sourceCode
    case pdf
    case image

    public var humanDescription: String {
        switch self {
        case .markdown: return "Markdown"
        case .csv: return "CSV"
        case .json: return "JSON"
        case .text: return "text"
        case .sourceCode: return "source"
        case .pdf: return "PDF"
        case .image: return "image"
        }
    }
}

let sourceCodeExtensions: Set<String> = [
    "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cs", "java", "kt", "kts",
    "go", "rs", "rb", "py", "js", "mjs", "cjs", "jsx", "ts", "tsx", "php", "pl",
    "lua", "r", "dart", "scala", "clj", "ex", "exs", "erl", "hs", "sh", "bash",
    "zsh", "fish", "sql", "html", "htm", "css", "scss", "less", "vue", "svelte",
    "gradle", "cmake", "podspec", "rake", "ipynb"
]

let plainTextExtensions: Set<String> = [
    "txt", "text", "env", "yaml", "yml", "log", "toml", "ini", "cfg", "conf",
    "properties", "xml", "plist", "rtf", "tex", "org", "rst", "srt", "vtt", "diff", "patch"
]

public func attachmentKind(for name: String) -> Option<AttachmentKind> {
    let ext = (name as NSString).pathExtension.lowercased()
    if ext.isEmpty { return .some(.text) }
    if sourceCodeExtensions.contains(ext) { return .some(.sourceCode) }
    if plainTextExtensions.contains(ext) { return .some(.text) }
    switch ext {
    case "md", "markdown": return .some(.markdown)
    case "csv", "tsv": return .some(.csv)
    case "json", "jsonl", "geojson": return .some(.json)
    case "pdf": return .some(.pdf)
    case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp": return .some(.image)
    default: return .none()
    }
}

public func textIfReadable(_ prefix: Data) -> Option<AttachmentKind> {
    guard !prefix.isEmpty, !prefix.contains(0) else { return .none() }
    return String(data: prefix, encoding: .utf8).map { _ in AttachmentKind.text }
        |> Option.fromOptional
}

public let attachmentSniffBytes = 4_096

public let attachmentLimit = 5

public let attachmentMaxBytes = 5_000_000

public enum AttachmentError: Error, Equatable, Sendable {
    case unsupported(name: String)
    case tooLarge(name: String, bytes: Int)
    case tooMany(limit: Int)
    case copyFailed(name: String, message: String)

    public var reason: String {
        switch self {
        case .unsupported(let name):
            return "I can't take \(name) — it isn't text, and it isn't a kind of file I can open. Markdown, CSV, JSON, PDFs, source code, notes and images all work."
        case .tooLarge(let name, let bytes):
            return "\(name) is \(bytes / 1_000_000)MB, which is more than I can send in one message."
        case .tooMany(let limit):
            return "That's more than \(limit) files — send the rest in the next message."
        case .copyFailed(let name, let message):
            return "I couldn't take a copy of \(name) — \(message)"
        }
    }
}

public func admitting(
    name: String,
    bytes: Int,
    to existing: [Attachment],
    limit: Int = attachmentLimit,
    sniffed: Option<AttachmentKind> = .none()
) -> Either<AttachmentError, AttachmentKind> {
    guard existing.count < limit else { return .left(.tooMany(limit: limit)) }
    guard bytes <= attachmentMaxBytes else { return .left(.tooLarge(name: name, bytes: bytes)) }
    return attachmentKind(for: name).orElse(sniffed)
        .fold({ .left(.unsupported(name: name)) }, { .right($0) })
}

public func attachmentDropPrompt(attached: Int, limit: Int = attachmentLimit) -> String {
    let room = limit - attached
    guard room > 0 else {
        return "Already holding \(limit) — send these before adding more"
    }
    return attached == 0
        ? "Drop a file — anywhere in this window"
        : "Drop to add — room for \(room) more"
}

public func attachmentNote(_ attachments: [Attachment]) -> String {
    guard !attachments.isEmpty else { return "" }
    let listed = attachments.map { "- \($0.name) (\($0.kind.humanDescription)): \($0.stagedURL.path)" }
    return """

    [The person attached \(attachments.count == 1 ? "a file" : "\(attachments.count) files") \
    to this message. Open \(attachments.count == 1 ? "it" : "them") yourself and use \
    \(attachments.count == 1 ? "its" : "their") contents as the data for what they asked:
    \(listed.joined(separator: "\n"))]
    """
}

public func attachmentLine(_ attachment: Attachment) -> String {
    "📎 \(attachment.name)"
}

public protocol AttachmentStaging: AnyObject, Sendable {
    var stagingDirectory: Option<URL> { get }
    func stage(_ url: URL, existing: [Attachment]) -> Either<AttachmentError, Attachment>
    func clear()
}

public final class FileAttachmentStore: AttachmentStaging, @unchecked Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileAttachmentStore.defaultDirectory
    }

    public static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    public var stagingDirectory: Option<URL> { .some(directory) }

    public func stage(_ url: URL, existing: [Attachment]) -> Either<AttachmentError, Attachment> {
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let theNameAlreadySaidWhatKindItIs = attachmentKind(for: name).isDefined
        let sniffed = theNameAlreadySaidWhatKindItIs
            ? Option<AttachmentKind>.none()
            : textIfReadable(FileAttachmentStore.prefix(of: url))
        return admitting(name: name, bytes: size, to: existing, sniffed: sniffed).flatMap { kind in
            let id = UUID()
            let prefixSoTwoFilesOfTheSameNameDoNotOverwriteEachOther = id.uuidString.prefix(8)
            let destination = self.directory
                .appendingPathComponent("\(prefixSoTwoFilesOfTheSameNameDoNotOverwriteEachOther)-\(name)")
            return attempt {
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
            }
            .mapLeft { AttachmentError.copyFailed(name: name, message: $0.localizedDescription) }
            .map { Attachment(id: id, name: name, stagedURL: destination, kind: kind) }^
        }^
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func prefix(of url: URL, bytes: Int = attachmentSniffBytes) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: bytes)) ?? Data()
    }
}

public final class InMemoryAttachmentStore: AttachmentStaging, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var cleared = 0
    public var sizes: [String: Int] = [:]

    public init() {}

    public var stagingDirectory: Option<URL> { .none() }

    public func stage(_ url: URL, existing: [Attachment]) -> Either<AttachmentError, Attachment> {
        let name = url.lastPathComponent
        return admitting(name: name, bytes: sizes[name] ?? 1_000, to: existing)
            .map { Attachment(name: name, stagedURL: URL(fileURLWithPath: "/staged/\(name)"), kind: $0) }^
    }

    public func clear() { lock.withLock { cleared += 1 } }
}

public struct AttachBlock: Equatable, Sendable {
    public let body: String
    public let asking: String?

    static let fence = "```attach"

    public init(body: String, asking: String?) {
        self.body = body
        self.asking = asking
    }

    public static func parse(_ text: String) -> AttachBlock {
        guard let (body, lines) = FencedBlock.split(text, fence: fence) else {
            return AttachBlock(body: text, asking: nil)
        }
        let asking = lines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return AttachBlock(body: body, asking: asking.isEmpty ? "a file" : asking)
    }
}
