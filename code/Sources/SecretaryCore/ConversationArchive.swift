import FunctionalCore
import Foundation

public struct ArchivedConversation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let savedAt: Date
    public let sessionID: Option<String>
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

public let conversationHistoryLimit = 10

func isCommand(_ entry: TranscriptEntry) -> Bool {
    entry.speaker == .user
        && entry.kind == .message
        && entry.text.trimmingCharacters(in: .whitespaces).hasPrefix("/")
}

public func worthArchiving(_ entries: [TranscriptEntry], relayed: Bool = false) -> Bool {
    relayed || entries.contains { $0.speaker == .user && $0.kind == .message && !isCommand($0) }
}

public func archivableEntries(_ entries: [TranscriptEntry]) -> [TranscriptEntry] {
    guard let last = entries.last, isCommand(last) else { return entries }
    return entries.dropLast()
}

public func conversationTitle(from entries: [TranscriptEntry], limit: Int = 42) -> String {
    let opening = entries.first {
        $0.speaker == .user && $0.kind == .message && !isCommand($0)
    }?.text ?? ""
    let collapsed = opening
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    guard !collapsed.isEmpty else { return "Untitled conversation" }
    guard collapsed.count > limit else { return collapsed }
    let cut = collapsed.prefix(limit)
    let stem = cut.lastIndex(of: " ").map { cut.distance(from: cut.startIndex, to: $0) > limit / 2 ? String(cut[..<$0]) : String(cut) } ?? String(cut)
    return stem + "…"
}

public func archiving(
    _ conversation: ArchivedConversation,
    into history: [ArchivedConversation],
    limit: Int = conversationHistoryLimit
) -> [ArchivedConversation] {
    ([conversation] + history.filter { $0.id != conversation.id }).prefix(limit).map { $0 }
}

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

public struct ConversationMenuRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String
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

public final class FileConversationStore: ConversationStoring, @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileConversationStore.defaultURL
    }

    public static var defaultURL: URL {
        supportDirectory.appendingPathComponent("conversations.json")
    }

    public static func url(forCharacter id: UUID) -> URL {
        supportDirectory.appendingPathComponent("conversations-\(id.uuidString).json")
    }

    private static var supportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
    }

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
