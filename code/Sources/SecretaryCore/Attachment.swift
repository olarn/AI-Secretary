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
    /// `key: value` lines, .env-shaped notes, plain text — and anything else
    /// whose bytes turn out to be text.
    case text
    /// A file of code. Its own kind rather than plain text because saying
    /// "Swift" in the chip and in the note is the difference between "here is
    /// a file" and "here is the thing you asked to look at".
    case sourceCode
    /// Read by the model, not by us: a PDF is a container, and the words in it
    /// are the point.
    case pdf
    /// A picture with words in it — a screenshot of a form, a photo of a
    /// receipt. The model reads it; nothing here tries to.
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

/// Extensions that say "this is code", so the chip and the note can say so
/// too.
///
/// A list, and it will always be missing someone's language — which is exactly
/// why nothing depends on it being complete. A file whose extension isn't here
/// still gets in as text if its bytes are text; all this list changes is what
/// the person and the model are told it is.
let sourceCodeExtensions: Set<String> = [
    "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cs", "java", "kt", "kts",
    "go", "rs", "rb", "py", "js", "mjs", "cjs", "jsx", "ts", "tsx", "php", "pl",
    "lua", "r", "dart", "scala", "clj", "ex", "exs", "erl", "hs", "sh", "bash",
    "zsh", "fish", "sql", "html", "htm", "css", "scss", "less", "vue", "svelte",
    "gradle", "cmake", "podspec", "rake", "ipynb"
]

/// Extensions that are worth naming as text even before the bytes are looked
/// at — configuration and prose formats a person hands over constantly.
let plainTextExtensions: Set<String> = [
    "txt", "text", "env", "yaml", "yml", "log", "toml", "ini", "cfg", "conf",
    "properties", "xml", "plist", "rtf", "tex", "org", "rst", "srt", "vtt", "diff", "patch"
]

/// The kind a file's name implies, or nothing when the name doesn't say.
///
/// By extension, not by sniffing — for the kinds that change how the file is
/// *described*. A person choosing a file knows what they chose, and guessing
/// past the name would mean treating a `.txt` as a CSV because it had commas in
/// it. When the name says nothing at all, the bytes get a turn: see
/// `textIfReadable`.
public func attachmentKind(for name: String) -> Option<AttachmentKind> {
    // `.env`, `.gitignore`, `Makefile`: no extension, and `pathExtension` says
    // so, which had them refused as an unknown format. A name with nothing
    // after a dot is a text file by convention on this platform, and reading
    // one as text is the mildest thing that could be wrong.
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

/// Whether a file the name couldn't place is text after all.
///
/// The alternative was a list of extensions that grows every time someone
/// hands over a format nobody thought of — and the list is never the point,
/// because what the model needs is only whether it can read the thing. So the
/// name decides the *description*, and for anything left over the bytes decide
/// admission: valid UTF-8 with no NUL in the first stretch is text.
///
/// A prefix rather than the whole file, because a 4MB log has to be answered
/// as fast as a 4KB note, and a file that is text for its first few thousand
/// bytes and binary after that is not a case worth being slow for.
public func textIfReadable(_ prefix: Data) -> Option<AttachmentKind> {
    guard !prefix.isEmpty, !prefix.contains(0) else { return .none() }
    return String(data: prefix, encoding: .utf8).map { _ in AttachmentKind.text }
        |> Option.fromOptional
}

/// How much of an unnamed file is looked at before deciding it is text.
public let attachmentSniffBytes = 4_096

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

/// Whether one more file may join the list, given what it is and how big it is.
///
/// Pure, and separate from the copying, so the rules can be read and tested
/// without a filesystem. Size arrives as a number for the same reason.
public func admitting(
    name: String,
    bytes: Int,
    to existing: [Attachment],
    limit: Int = attachmentLimit,
    sniffed: Option<AttachmentKind> = .none()
) -> Either<AttachmentError, AttachmentKind> {
    guard existing.count < limit else { return .left(.tooMany(limit: limit)) }
    guard bytes <= attachmentMaxBytes else { return .left(.tooLarge(name: name, bytes: bytes)) }
    // The name first, the bytes second. A `.swift` file is source whatever its
    // first four kilobytes look like; a `.bak` is whatever it turns out to be.
    return attachmentKind(for: name).orElse(sniffed)
        .fold({ .left(.unsupported(name: name)) }, { .right($0) })
}

/// What the drop area says while a file is being dragged over the window.
///
/// It has to be able to say no. The window accepts a drop anywhere, so the
/// person can be holding a sixth file over a list that is already full — and an
/// area still reading "drop files here" would invite exactly the drop that
/// `admitting` then refuses, with the refusal arriving after they let go.
/// Saying it before the drop is the only place it helps.
public func attachmentDropPrompt(attached: Int, limit: Int = attachmentLimit) -> String {
    let room = limit - attached
    guard room > 0 else {
        return "Already holding \(limit) — send these before adding more"
    }
    return attached == 0
        ? "Drop a file — anywhere in this window"
        : "Drop to add — room for \(room) more"
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
        // Only when the name didn't say. Opening every file to look at it would
        // make an ordinary `.csv` wait on a read it doesn't need.
        let sniffed = attachmentKind(for: name).isDefined
            ? Option<AttachmentKind>.none()
            : textIfReadable(FileAttachmentStore.prefix(of: url))
        return admitting(name: name, bytes: size, to: existing, sniffed: sniffed).flatMap { kind in
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

    /// The first few kilobytes, or nothing if the file can't be opened. Read
    /// through a handle rather than `Data(contentsOf:)` so a large file doesn't
    /// come into memory to answer a question about its first page.
    static func prefix(of url: URL, bytes: Int = attachmentSniffBytes) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: bytes)) ?? Data()
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
