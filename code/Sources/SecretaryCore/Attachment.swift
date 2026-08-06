import FunctionalCore
import Foundation

/// A file the person has handed over for this message.
///
/// The point of it is data entry: "here is the list, put it into that web app".
/// Typing a table into a chat box is the part nobody wants to do, so the file
/// itself comes across — dragged onto the input, or picked from the panel the
/// assistant can ask for.
///
/// Deliberately *staged*, not linked. The file is copied into the app's own
/// folder and the model is pointed at the copy. Pointing it at the original
/// would mean opening the folder the file came from — drop something off the
/// Desktop and the whole Desktop becomes readable for the session, which is a
/// far wider thing than the person did. The copy is also a snapshot: the answer
/// describes the file that was handed over, not whatever it became halfway
/// through the turn.
public struct Attachment: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// What it is called, as the person knows it.
    public let name: String
    /// Where the copy lives. Inside the app's own folder, always.
    public let stagedURL: URL
    public let kind: AttachmentKind

    public init(id: UUID = UUID(), name: String, stagedURL: URL, kind: AttachmentKind) {
        self.id = id
        self.name = name
        self.stagedURL = stagedURL
        self.kind = kind
    }
}

/// What kind of thing the file is, as far as it matters here: enough to tell
/// the model what it is being handed, and to refuse what it can't use.
///
/// No parsers. The model reads the file with its own tools — a CSV parser, a
/// key-value parser and a "sort of JSON" parser written here would be three
/// things to maintain that are each worse than what already reads them, and the
/// fourth format would still arrive.
public enum AttachmentKind: String, Equatable, Sendable, CaseIterable {
    case markdown
    case csv
    case json
    /// `key: value` lines, .env-shaped notes, plain text.
    case text
    /// A picture with words in it — a screenshot of a form, a photo of a
    /// receipt. The model reads it; nothing here tries to.
    case image

    public var humanDescription: String {
        switch self {
        case .markdown: return "Markdown"
        case .csv: return "CSV"
        case .json: return "JSON"
        case .text: return "text"
        case .image: return "image"
        }
    }
}

/// The kind a file's name implies, or nothing when it isn't one this can use.
///
/// By extension, not by sniffing the bytes. A person choosing a file knows what
/// they chose, and a mismatch between the name and the content is theirs to
/// see — guessing past the name would mean silently treating a `.txt` as a CSV
/// because it had commas in it.
public func attachmentKind(for name: String) -> Option<AttachmentKind> {
    // `.env`, `.gitignore`, `Makefile`: no extension, and `pathExtension` says
    // so, which had them refused as an unknown format. A name with nothing
    // after a dot is a text file by convention on this platform, and reading
    // one as text is the mildest thing that could be wrong.
    let ext = (name as NSString).pathExtension.lowercased()
    if ext.isEmpty { return .some(.text) }
    switch ext {
    case "md", "markdown": return .some(.markdown)
    case "csv", "tsv": return .some(.csv)
    case "json": return .some(.json)
    case "txt", "text", "env", "yaml", "yml", "log": return .some(.text)
    case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp": return .some(.image)
    default: return .none()
    }
}

/// How many files may ride along on one message.
///
/// Five, because each one is read in full on the turn it arrives and the
/// person can still see all five at once above the input. A cap that can be
/// exceeded quietly isn't one.
public let attachmentLimit = 5

/// Largest file that may be handed over, in bytes. The same order as the file
/// understanding cap and for the same reason: bytes on screen are free, bytes
/// on the wire are not.
public let attachmentMaxBytes = 5_000_000

public enum AttachmentError: Error, Equatable, Sendable {
    case unsupported(name: String)
    case tooLarge(name: String, bytes: Int)
    case tooMany(limit: Int)
    case copyFailed(name: String, message: String)

    /// Said to the person, in the chat, in their terms.
    public var reason: String {
        switch self {
        case .unsupported(let name):
            return "I can't take \(name) — I can read Markdown, CSV, JSON, plain text and images."
        case .tooLarge(let name, let bytes):
            return "\(name) is \(bytes / 1_000_000)MB, which is more than I can send in one message."
        case .tooMany(let limit):
            return "That's more than \(limit) files — send the rest in the next message."
        case .copyFailed(let name, let message):
            return "I couldn't take a copy of \(name) — \(message)"
        }
    }
}

/// Whether one more file may join the list, given what it is and how big it is.
///
/// Pure, and separate from the copying, so the rules can be read and tested
/// without a filesystem. Size arrives as a number for the same reason.
public func admitting(
    name: String,
    bytes: Int,
    to existing: [Attachment],
    limit: Int = attachmentLimit
) -> Either<AttachmentError, AttachmentKind> {
    guard existing.count < limit else { return .left(.tooMany(limit: limit)) }
    guard bytes <= attachmentMaxBytes else { return .left(.tooLarge(name: name, bytes: bytes)) }
    return attachmentKind(for: name)
        .fold({ .left(.unsupported(name: name)) }, { .right($0) })
}

/// What the model is told about the files riding along with this message.
///
/// Paths, not contents. The assistant has file tools and the staged copies sit
/// in a folder it has been given, so it opens them itself — the same rule the
/// rest of the app follows, and the only one that works for a picture.
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

/// How an attachment reads in the transcript, under the message it came with.
public func attachmentLine(_ attachment: Attachment) -> String {
    "📎 \(attachment.name)"
}

// MARK: - Staging

public protocol AttachmentStaging: AnyObject, Sendable {
    /// The folder the copies live in, when there is one. Handed to the backend
    /// so it can open what was staged — and nothing else.
    var stagingDirectory: Option<URL> { get }
    /// Copies a chosen file into the app's own folder and describes the copy.
    func stage(_ url: URL, existing: [Attachment]) -> Either<AttachmentError, Attachment>
    /// Throws away every staged copy. Called when a conversation ends — the
    /// files were handed over for a conversation, and keeping them past it
    /// would leave someone's spreadsheet in Application Support forever.
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
        return admitting(name: name, bytes: size, to: existing).flatMap { kind in
            // The copy keeps the person's own filename, prefixed so two files
            // called `data.csv` from different folders don't overwrite each
            // other — the model is told the plain name either way.
            let id = UUID()
            let destination = self.directory
                .appendingPathComponent("\(id.uuidString.prefix(8))-\(name)")
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
}

/// Stands in for the disk. Keeps the same rules — the refusals are what most
/// tests are about — but stages nowhere.
public final class InMemoryAttachmentStore: AttachmentStaging, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var cleared = 0
    /// Sizes to report for named files, so a test can hand over a large one.
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

// MARK: - The assistant asking for a file

/// The assistant asking the app to put an open-file button in front of the
/// person.
///
/// ```attach
/// the spreadsheet with the rows to enter
/// ```
///
/// Marked rather than inferred, like every other block: a reply that merely
/// mentions a file must not open a file dialog. What it buys is that the
/// person never has to know where the file is in a path — they press a button
/// and choose it, which is also the only way this would work sandboxed.
public struct AttachBlock: Equatable, Sendable {
    public let body: String
    /// What the assistant says it is asking for, shown on the button's line.
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
