import FunctionalCore
import Foundation

/// A conversation that has been put away, so starting a new one doesn't destroy
/// the last one.
///
/// Two different things have to come back when this is reopened, and confusing
/// them is the whole risk of the feature: `entries` is what was *said* — the
/// words the person already read — and `sessionID` is what the model
/// *remembers*. Restoring the first without the second gives you a transcript
/// full of context the model has no knowledge of, which reads as the app having
/// quietly lost its mind mid-sentence. Whenever the second can't be restored,
/// that has to be said out loud rather than papered over.
public struct ArchivedConversation: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// What the menu calls it. Derived once, when the conversation is put away,
    /// and stored — a title that recomputed itself would change under the
    /// person as the derivation improved.
    public let title: String
    public let savedAt: Date
    /// Claude Code's own session for this thread. Absent when the conversation
    /// never reached the model — the person typed, the turn failed, and there
    /// is nothing on the other side to resume.
    public let sessionID: Option<String>
    /// The project this ran in, held by id and never by path.
    ///
    /// `ProjectStore` keeps paths out of chat history on purpose, and this file
    /// is chat history. The path is looked up through the registry at the
    /// moment of resuming, so a project that has since been removed resolves to
    /// nothing rather than to a stale directory we'd then hand to a tool.
    public let projectID: Option<UUID>
    public let entries: [TranscriptEntry]

    public init(
        id: UUID = UUID(),
        title: String,
        savedAt: Date = Date(),
        sessionID: Option<String> = .none(),
        projectID: Option<UUID> = .none(),
        entries: [TranscriptEntry]
    ) {
        self.id = id
        self.title = title
        self.savedAt = savedAt
        self.sessionID = sessionID
        self.projectID = projectID
        self.entries = entries
    }
}

/// How many conversations the menu keeps.
///
/// A menu is a list you read at a glance; past a screenful it stops being one.
public let conversationHistoryLimit = 10

/// Whether the person said this to the assistant, or to the app.
///
/// A slash command is an instruction to the program — `/new`, `/history 2`,
/// `/model sonnet`. It appears in the transcript because seeing what you typed
/// is how you know it registered, but it isn't part of a conversation, and
/// treating it as one produced a history row literally titled "/history 1":
/// reopening a conversation archived the command used to reopen it.
func isCommand(_ entry: TranscriptEntry) -> Bool {
    entry.speaker == .user
        && entry.kind == .message
        && entry.text.trimmingCharacters(in: .whitespaces).hasPrefix("/")
}

/// Whether this conversation is worth keeping at all.
///
/// The rule is that somebody said something. Opening the app, watching the
/// greeting arrive and pressing New Conversation must not leave a row behind —
/// the history would fill with threads nobody had, and the ten real ones would
/// fall off the end to make room for them.
///
/// `relayed` is the second way for something to have happened, and it exists
/// because of what "somebody" quietly meant: a `.user` turn. A character who
/// spent her whole conversation doing another character's errand never has one
/// — every line in her transcript is hers — so the entire exchange was dropped
/// on the floor. Measured on 2026-08-14: Pikachu and Ditto both answered a
/// relayed request, both showed it on screen, and neither conversation file was
/// touched, while the character who *sent* it filed hers normally.
public func worthArchiving(_ entries: [TranscriptEntry], relayed: Bool = false) -> Bool {
    relayed || entries.contains { $0.speaker == .user && $0.kind == .message && !isCommand($0) }
}

/// The conversation as it should be filed.
///
/// Commands stay where they fall — `/model sonnet` halfway down explains why
/// the answers change tone after it, and removing it would leave a conversation
/// that doesn't account for itself. The exception is the last line, which is
/// the command that closed the conversation and belongs to what happens next
/// rather than to what was said.
public func archivableEntries(_ entries: [TranscriptEntry]) -> [TranscriptEntry] {
    guard let last = entries.last, isCommand(last) else { return entries }
    return entries.dropLast()
}

/// What to call a conversation in the menu.
///
/// The first thing the person asked for, shortened. Deliberately derived rather
/// than generated: asking the model for a title costs a turn, can fail, and can
/// be slow at exactly the moment the person is trying to start something else —
/// three failure modes for a menu label. The opening question is also what
/// people actually search their own memory by.
public func conversationTitle(from entries: [TranscriptEntry], limit: Int = 42) -> String {
    let opening = entries.first {
        $0.speaker == .user && $0.kind == .message && !isCommand($0)
    }?.text ?? ""
    let collapsed = opening
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    guard !collapsed.isEmpty else { return "Untitled conversation" }
    guard collapsed.count > limit else { return collapsed }
    // Cut on a word boundary when there is one near the end, so a title doesn't
    // break in the middle of a word — but never search so far back that a long
    // first word leaves a stub.
    let cut = collapsed.prefix(limit)
    let stem = cut.lastIndex(of: " ").map { cut.distance(from: cut.startIndex, to: $0) > limit / 2 ? String(cut[..<$0]) : String(cut) } ?? String(cut)
    return stem + "…"
}

/// Puts a conversation at the front of the list and drops whatever no longer
/// fits.
///
/// Newest first, because that is the order they are looked for in, and it means
/// the cap always trims the end. Re-archiving a conversation already in the
/// list replaces it in place rather than appearing twice: resuming and putting
/// away again is one thread continuing, not two.
public func archiving(
    _ conversation: ArchivedConversation,
    into history: [ArchivedConversation],
    limit: Int = conversationHistoryLimit
) -> [ArchivedConversation] {
    ([conversation] + history.filter { $0.id != conversation.id }).prefix(limit).map { $0 }
}

/// What one row in the history menu reads as.
///
/// The title alone isn't enough to tell two of them apart — people ask the same
/// thing on different days — so the age rides along. Coarse on purpose: the
/// question a menu answers is "which one was that", not "at what minute", and a
/// clock time would have to be read and converted before it meant anything.
public func conversationMenuLabel(
    title: String,
    savedAt: Date,
    now: Date = Date()
) -> String {
    let days = Calendar.current.dateComponents([.day], from: savedAt, to: now).day ?? 0
    let when = switch days {
    case ..<1: "today"
    case 1: "yesterday"
    case 2..<7: "\(days) days ago"
    default: savedAt.formatted(.dateTime.day().month(.abbreviated))
    }
    return "\(title)  ·  \(when)"
}

/// One row of the history menu, already decided.
///
/// Plain Swift on purpose: this crosses into `AISecretaryApp`, which cannot
/// import `FunctionalCore` without Bow's `State` shadowing SwiftUI's. The menu
/// receives answers, not domain values to interrogate.
public struct ConversationMenuRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    /// The conversation currently on screen, when it came from this list.
    public let isCurrent: Bool

    public init(id: UUID, label: String, isCurrent: Bool) {
        self.id = id
        self.label = label
        self.isCurrent = isCurrent
    }
}

public func conversationMenuRows(
    _ history: [ArchivedConversation],
    current: Option<UUID> = .none(),
    now: Date = Date()
) -> [ConversationMenuRow] {
    history.map { conversation in
        ConversationMenuRow(
            id: conversation.id,
            label: conversationMenuLabel(title: conversation.title, savedAt: conversation.savedAt, now: now),
            isCurrent: current.toOptional() == conversation.id
        )
    }
}

// MARK: - Persistence

public enum ConversationStoreError: Error, Equatable, Sendable {
    case readFailed(path: String, message: String)
    case decodeFailed(path: String, message: String)
    case writeFailed(path: String, message: String)

    public var reason: String {
        switch self {
        case .readFailed(_, let message), .decodeFailed(_, let message), .writeFailed(_, let message):
            return message
        }
    }
}

public protocol ConversationStoring: AnyObject, Sendable {
    func load() -> Either<ConversationStoreError, [ArchivedConversation]>
    func save(_ conversations: [ArchivedConversation]) -> Either<ConversationStoreError, Void>
}

/// The transfer shape. `TranscriptEntry.id` is a `let` with an inline default
/// and `Option` has no `Codable`, so neither type can be encoded directly.
struct ArchivedConversationDTO: Codable {
    struct Entry: Codable {
        var speaker: String
        var kind: String
        var text: String
        var timestamp: Date
        var speakerName: String
    }

    var id: UUID
    var title: String
    var savedAt: Date
    var sessionID: String?
    var projectID: UUID?
    var entries: [Entry]
}

extension ArchivedConversationDTO.Entry {
    init(_ entry: TranscriptEntry) {
        speaker = entry.speaker == .user ? "user" : "secretary"
        kind = switch entry.kind {
        case .message: "message"
        case .activity: "activity"
        case .failure: "failure"
        case .divider: "divider"
        }
        text = entry.text
        timestamp = entry.timestamp
        speakerName = entry.speakerName
    }

    /// An unreadable kind becomes a plain message rather than being dropped: a
    /// file written by a newer build should cost the person a differently-styled
    /// line, not a hole in a conversation they read.
    private var domainKind: TranscriptEntry.Kind {
        switch kind {
        case "activity": .activity
        case "failure": .failure
        case "divider": .divider
        default: .message
        }
    }

    var domain: TranscriptEntry {
        TranscriptEntry(
            speaker: speaker == "user" ? .user : .secretary,
            kind: domainKind,
            text: text,
            timestamp: timestamp,
            speakerName: speakerName
        )
    }
}

extension ArchivedConversationDTO {
    init(_ conversation: ArchivedConversation) {
        id = conversation.id
        title = conversation.title
        savedAt = conversation.savedAt
        sessionID = conversation.sessionID.toOptional()
        projectID = conversation.projectID.toOptional()
        entries = conversation.entries.map(Entry.init)
    }

    var domain: ArchivedConversation {
        ArchivedConversation(
            id: id,
            title: title,
            savedAt: savedAt,
            sessionID: Option.fromOptional(sessionID),
            projectID: Option.fromOptional(projectID),
            entries: entries.map(\.domain)
        )
    }
}

/// Keeps the history as JSON under Application Support, beside the registry.
///
/// Failures come back as values for the same reason `FileProjectStore`'s do:
/// this is read at launch, and an unreadable history file must cost the person
/// their old conversations, not their app.
public final class FileConversationStore: ConversationStoring, @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileConversationStore.defaultURL
    }

    /// Where history lived while there was one character. Still read once, to
    /// be adopted — see `conversationFileMigration`.
    public static var defaultURL: URL {
        supportDirectory.appendingPathComponent("conversations.json")
    }

    /// One file per character. A character's conversations are hers, and a
    /// single file holding everybody's would have to carry an owner on every
    /// row and be rewritten by whichever character saved last.
    public static func url(forCharacter id: UUID) -> URL {
        supportDirectory.appendingPathComponent("conversations-\(id.uuidString).json")
    }

    private static var supportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
    }

    /// Hands the pre-Phase-13 history file to a character, once.
    ///
    /// The decision is `conversationFileMigration`; this reads the two `exists`
    /// answers off the disk and applies what it says. Returns what it decided
    /// so a caller can see whether anything moved.
    @discardableResult
    public static func adoptLegacyHistory(
        for id: UUID,
        fileManager: FileManager = .default
    ) -> Either<ConversationStoreError, ConversationFileMigration> {
        let legacy = defaultURL
        let mine = url(forCharacter: id)
        let decision = conversationFileMigration(
            legacy: legacy,
            perCharacter: mine,
            legacyExists: fileManager.fileExists(atPath: legacy.path),
            perCharacterExists: fileManager.fileExists(atPath: mine.path)
        )
        guard case .adopt(let from, let to) = decision else { return .right(decision) }
        return attempt {
            try fileManager.createDirectory(
                at: to.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: from, to: to)
        }
        .mapLeft { ConversationStoreError.writeFailed(path: to.path, message: $0.localizedDescription) }^
        .map { decision }^
    }

    public func load() -> Either<ConversationStoreError, [ArchivedConversation]> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .right([]) }
        return readData().flatMap(decode)^
    }

    private func readData() -> Either<ConversationStoreError, Data> {
        attempt { try Data(contentsOf: fileURL) }
            .mapLeft { .readFailed(path: fileURL.path, message: $0.localizedDescription) }^
    }

    private func decode(_ data: Data) -> Either<ConversationStoreError, [ArchivedConversation]> {
        attempt { try JSONDecoder().decode([ArchivedConversationDTO].self, from: data) }
            .mapLeft { ConversationStoreError.decodeFailed(path: fileURL.path, message: $0.localizedDescription) }^
            .map { $0.map(\.domain) }^
    }

    public func save(_ conversations: [ArchivedConversation]) -> Either<ConversationStoreError, Void> {
        attempt {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(conversations.map(ArchivedConversationDTO.init)).write(to: fileURL, options: .atomic)
        }
        .mapLeft { .writeFailed(path: fileURL.path, message: $0.localizedDescription) }^
    }
}

public final class InMemoryConversationStore: ConversationStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var conversations: [ArchivedConversation]

    public init(conversations: [ArchivedConversation] = []) {
        self.conversations = conversations
    }

    public func load() -> Either<ConversationStoreError, [ArchivedConversation]> {
        .right(lock.withLock { conversations })
    }

    public func save(_ conversations: [ArchivedConversation]) -> Either<ConversationStoreError, Void> {
        lock.withLock { self.conversations = conversations }
        return .right(())
    }
}
