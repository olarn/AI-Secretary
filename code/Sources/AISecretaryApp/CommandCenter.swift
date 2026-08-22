import Foundation
import Permissions
import SecretaryCore

struct DroppedInstruction: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let text: String
}

struct DroppedAttachment: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL
}

struct CommandResult: Identifiable, Equatable {
    let id = UUID()
    let characterID: UUID
    let name: String
    let text: String
    let succeeded: Bool
    let receivedAt: Date
    var choices: [String]
}

struct CommandApproval: Identifiable, Equatable {
    let characterID: UUID
    let name: String
    let question: String
    let answers: [PermissionAnswer]

    var id: UUID { characterID }
}

@MainActor
@Observable
final class CommandCenter {
    @ObservationIgnored let roster: () -> [CharacterCard]
    @ObservationIgnored let deliver: (UUID, String, [URL]) -> Void
    @ObservationIgnored let endSessions: (Set<UUID>) -> Void
    @ObservationIgnored let answerApproval: (UUID, PermissionAnswer) -> Void

    var selected: Set<UUID> = []
    var draft = ""
    var errorText: String?
    var droppedFiles: [DroppedInstruction] = []
    var pendingAttachments: [DroppedAttachment] = []
    private(set) var commanded: Set<UUID> = []
    var focusRequests = 0
    var slabWidth: Double = commandWindowDefaultWidth
    var extraBoxHeight: Double = 0
    var fontSize: Double = {
        let saved = UserDefaults.standard.double(forKey: commandFontSizeKey)
        return clampedCommandFontSize(saved > 0 ? saved : commandWindowDefaultFontSize)
    }()
    private(set) var results: [CommandResult] = []
    var showResults = true
    private(set) var approvals: [CommandApproval] = []

    private(set) var sentCommands: [String] = []
    private var recallIndex: Int?
    private var stashedDraft = ""

    init(
        roster: @escaping () -> [CharacterCard],
        deliver: @escaping (UUID, String, [URL]) -> Void,
        endSessions: @escaping (Set<UUID>) -> Void,
        answerApproval: @escaping (UUID, PermissionAnswer) -> Void
    ) {
        self.roster = roster
        self.deliver = deliver
        self.endSessions = endSessions
        self.answerApproval = answerApproval
    }

    func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        errorText = nil
    }

    func attach(_ url: URL) {
        switch commandDropRole(forExtension: url.pathExtension) {
        case .instruction:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                errorText = "Couldn't read \(url.lastPathComponent)"
                return
            }
            droppedFiles.append(DroppedInstruction(name: url.lastPathComponent, text: text))
        case .attachment:
            pendingAttachments.append(DroppedAttachment(name: url.lastPathComponent, url: url))
        }
        errorText = nil
    }

    func detach(_ id: UUID) {
        droppedFiles.removeAll { $0.id == id }
        pendingAttachments.removeAll { $0.id == id }
    }

    func clearComposition() {
        draft = ""
        droppedFiles = []
        pendingAttachments = []
        errorText = nil
        recallIndex = nil
    }

    func send() -> Bool {
        let cards = roster()
        let typed = draft
        let text = mergedInstructions(files: droppedFiles.map(\.text), typed: typed)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return false }

        let dispatch = commandRecipients(
            for: text,
            selected: cards.filter { selected.contains($0.id) },
            roster: cards
        )
        switch dispatch {
        case .needSelection:
            errorText = selectAtLeastOneCharacterMessage
            return false
        case .namedNotSelected(let names):
            errorText = namedNotSelectedMessage(names)
            return false
        case .send(let recipients):
            let files = pendingAttachments.map(\.url)
            recipients.forEach { recipient in
                deliver(
                    recipient.id,
                    commandMessage(for: recipient, among: recipients, instructions: text),
                    files
                )
            }
            commanded.formUnion(recipients.map(\.id))
            if !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentCommands.append(typed)
            }
            draft = ""
            droppedFiles = []
            pendingAttachments = []
            errorText = nil
            recallIndex = nil
            return true
        }
    }

    var hasRecallHistory: Bool { !sentCommands.isEmpty }

    func recallOlder() -> Bool {
        guard !sentCommands.isEmpty else { return false }
        switch recallIndex {
        case nil:
            stashedDraft = draft
            recallIndex = sentCommands.count - 1
        case let index? where index > 0:
            recallIndex = index - 1
        default:
            break
        }
        draft = recallIndex.map { sentCommands[$0] } ?? draft
        return true
    }

    func recallNewer() -> Bool {
        guard let index = recallIndex else { return false }
        if index + 1 < sentCommands.count {
            recallIndex = index + 1
            draft = sentCommands[recallIndex ?? index]
        } else {
            recallIndex = nil
            draft = stashedDraft
        }
        return true
    }

    func record(_ turn: FinishedTurn, from id: UUID) {
        guard commanded.contains(id) else { return }
        results.insert(
            CommandResult(
                characterID: id,
                name: turn.characterName,
                text: MessageChoices.parse(turn.text).body
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                succeeded: turn.succeeded,
                receivedAt: Date(),
                choices: turn.choices
            ),
            at: 0
        )
        if results.count > 20 { results.removeLast(results.count - 20) }
    }

    func pick(_ option: String, from result: CommandResult) {
        deliver(result.characterID, option, [])
        commanded.insert(result.characterID)
        results = results.map { entry in
            guard entry.id == result.id else { return entry }
            var answered = entry
            answered.choices = []
            return answered
        }
    }

    var resultsMarkdown: String {
        commandResultsMarkdown(
            results.map {
                CommandTranscriptEntry(name: $0.name, text: $0.text, succeeded: $0.succeeded)
            }
        )
    }

    func clearResults() { results = [] }

    func record(_ asked: ApprovalAsked, from id: UUID) {
        guard commanded.contains(id) else { return }
        approvals.removeAll { $0.characterID == id }
        approvals.append(
            CommandApproval(
                characterID: id,
                name: asked.characterName,
                question: asked.question,
                answers: asked.answers
            )
        )
    }

    func approvalSettled(for id: UUID) {
        approvals.removeAll { $0.characterID == id }
    }

    func answer(_ permission: PermissionAnswer, to approval: CommandApproval) {
        approvals.removeAll { $0.characterID == approval.characterID }
        answerApproval(approval.characterID, permission)
    }

    func bumpFontSize(_ delta: Double) {
        fontSize = clampedCommandFontSize(fontSize + delta)
        UserDefaults.standard.set(fontSize, forKey: commandFontSizeKey)
    }

    func endAll() {
        endSessions(commanded)
        commanded = []
        approvals = []
    }
}
