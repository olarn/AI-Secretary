import Foundation
import Permissions
import SecretaryCore

/// One instruction file dropped on the command window, already read: the drop
/// is the moment the file exists for sure, and holding text rather than a URL
/// means nothing re-reads the disk at send time.
struct DroppedInstruction: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let text: String
}

/// A file riding along as a real attachment — an image, a PDF, a CSV. Held as
/// a URL because each recipient's own Secretary stages it, exactly as the
/// chat's drop does; reading it here would only be a second copy.
struct DroppedAttachment: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL
}

/// One finished turn of a commanded character, as the results strip shows it.
struct CommandResult: Identifiable, Equatable {
    let id = UUID()
    let characterID: UUID
    let name: String
    let text: String
    let succeeded: Bool
    /// The reply's own question, offered as buttons. Emptied once picked —
    /// the question has been answered, and a second click would answer it
    /// again.
    var choices: [String]
}

/// A commanded character's permission card, waiting for an answer here rather
/// than in her chat.
///
/// Keyed by the character, because she holds at most one `pendingDecision` at a
/// time: a second card from the same character replaces the first rather than
/// stacking, which is exactly what her own panel shows.
struct CommandApproval: Identifiable, Equatable {
    let characterID: UUID
    let name: String
    let question: String
    let answers: [PermissionAnswer]

    var id: UUID { characterID }
}

/// What the command window is holding: who is ticked, what is waiting to go,
/// who has been commanded, and what has come back.
///
/// Gathering and applying only. Every decision — who a command reaches, what
/// each copy says, how files merge and route — is a pure function in
/// `SecretaryCore`, because this target is never linked into the test bundle.
@MainActor
@Observable
final class CommandCenter {
    /// Everyone on the desktop, asked for rather than held — the same rule as
    /// `CharacterBus`, so a character added or deleted needs nothing rewired.
    @ObservationIgnored let roster: () -> [CharacterCard]
    /// Hands one character her copy of the command, with the files that ride
    /// along as attachments.
    @ObservationIgnored let deliver: (UUID, String, [URL]) -> Void
    /// Ends the sessions of everyone in the set.
    @ObservationIgnored let endSessions: (Set<UUID>) -> Void
    /// Answers one character's waiting permission card.
    ///
    /// Its own door rather than another `deliver` of the answer's words:
    /// `submit` opens by dropping whatever card is pending, so sending "Once"
    /// as a message would throw the question away and then ask her to do
    /// something called "Once".
    @ObservationIgnored let answerApproval: (UUID, PermissionAnswer) -> Void

    /// Who is ticked. Commands only ever reach ticked characters; the set can
    /// change at any time and takes effect on the next send.
    var selected: Set<UUID> = []
    /// The message being written. In the model rather than the view so the
    /// arrow-key monitor can consult it and recall can rewrite it — and so it
    /// survives the view being rebuilt when the borrowed look changes.
    var draft = ""
    /// The red line under the box, when there is one.
    var errorText: String?
    /// Instruction files waiting to go with the next send, in drop order —
    /// the order they merge in.
    var droppedFiles: [DroppedInstruction] = []
    /// Files waiting to go as attachments.
    var pendingAttachments: [DroppedAttachment] = []
    /// Everyone this window has sent a command to since the last
    /// "End all". Hiding the window does not touch it — hiding keeps
    /// sessions alive by design.
    private(set) var commanded: Set<UUID> = []
    /// Bumped by the controller when the window comes up, so the caret lands
    /// in the box — the same counter idiom as `ChatBubbleLayout`.
    var focusRequests = 0
    /// The slab's width. The controller owns changing it — edge resizes and
    /// the saved value both land here, and the view only draws it.
    var slabWidth: Double = commandWindowDefaultWidth
    /// Height the person granted beyond the minimum, all of it given to the
    /// message box — the owner's rule (2026-08-19): resizing taller grows the
    /// box, everything else keeps its place. Zero is the default, which is
    /// also the minimum.
    var extraBoxHeight: Double = 0
    /// The box's own text size, moved by ⌘+/⌘− while the box holds the caret.
    var fontSize: Double = {
        let saved = UserDefaults.standard.double(forKey: commandFontSizeKey)
        return clampedCommandFontSize(saved > 0 ? saved : commandWindowDefaultFontSize)
    }()
    /// What commanded characters have answered, newest first, capped so a
    /// long day of commands cannot grow the window without bound.
    private(set) var results: [CommandResult] = []
    /// The results strip folds — the owner asked for it closable.
    var showResults = true
    /// Cards waiting on the person, oldest first. Never folded away with the
    /// results: a question nobody can see is the bug this exists to fix.
    private(set) var approvals: [CommandApproval] = []

    /// What was sent from this box, for ↑↓ recall — this window's own, not
    /// any character's, and this session's only, same as the chat's.
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
        // The line said "tick somebody"; they just did. Leaving it up would
        // scold a state that no longer exists.
        errorText = nil
    }

    /// One door for the drop and the picker both; the role rule decides what
    /// the file becomes.
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

    /// The "Clear" link: everything composed but not yet sent. Not the
    /// results, and never the sessions.
    func clearComposition() {
        draft = ""
        droppedFiles = []
        pendingAttachments = []
        errorText = nil
        recallIndex = nil
    }

    /// Sends the draft and the waiting files. Returns whether they went.
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

    // MARK: - ↑↓ recall — the same walk the chat box does

    var hasRecallHistory: Bool { !sentCommands.isEmpty }

    /// Up: step back through what was sent, stashing the unsent draft first
    /// so stepping past the oldest and back down returns it intact.
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

    /// Down: forward again, ending on the stashed draft.
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

    // MARK: - Results

    /// A commanded character's turn came to rest. Anything she finishes while
    /// commanded lands here — hand-offs between recipients included, which is
    /// how divided work stays visible without opening her chat.
    func record(_ turn: FinishedTurn, from id: UUID) {
        guard commanded.contains(id) else { return }
        results.insert(
            CommandResult(
                characterID: id,
                name: turn.characterName,
                // Parsed again for the body: `FinishedTurn.text` still carries
                // the ```choices fence (driven 2026-08-19 — the strip showed
                // it as literal text under the buttons made from it).
                text: MessageChoices.parse(turn.text).body
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                succeeded: turn.succeeded,
                choices: turn.choices
            ),
            at: 0
        )
        // Newest first, oldest off the end — 20 is a strip, not an archive.
        if results.count > 20 { results.removeLast(results.count - 20) }
    }

    /// Answers one result's question with the option's own words, exactly as
    /// the chat's picker does — never a bare letter.
    func pick(_ option: String, from result: CommandResult) {
        deliver(result.characterID, option, [])
        commanded.insert(result.characterID)
        // The question has been answered; the buttons would answer it twice.
        results = results.map { entry in
            guard entry.id == result.id else { return entry }
            var answered = entry
            answered.choices = []
            return answered
        }
    }

    /// The strip as one document — what Save writes and what Copy puts on the
    /// clipboard, so the two can never disagree about what "the results" are.
    var resultsMarkdown: String {
        commandResultsMarkdown(
            results.map {
                CommandTranscriptEntry(name: $0.name, text: $0.text, succeeded: $0.succeeded)
            }
        )
    }

    func clearResults() { results = [] }

    // MARK: - Permission cards

    /// A commanded character is blocked and is asking. Same rule as `record`:
    /// only characters this window commanded, because a card raised in a chat
    /// the person opened themselves belongs in that chat.
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

    /// Her card is gone — she may have been answered in her own chat, or have
    /// dropped it. Either way the buttons here would answer nothing.
    func approvalSettled(for id: UUID) {
        approvals.removeAll { $0.characterID == id }
    }

    /// The person pressed Once / Always / Deny here. Taken off the strip
    /// immediately rather than waiting to be told it settled: she may go
    /// straight back to work, and buttons that linger read as unanswered.
    func answer(_ permission: PermissionAnswer, to approval: CommandApproval) {
        approvals.removeAll { $0.characterID == approval.characterID }
        answerApproval(approval.characterID, permission)
    }

    // MARK: - Text size

    /// ⌘+ / ⌘−. Persisted like the window's frame — a size chosen once is a
    /// preference, not a session whim.
    func bumpFontSize(_ delta: Double) {
        fontSize = clampedCommandFontSize(fontSize + delta)
        UserDefaults.standard.set(fontSize, forKey: commandFontSizeKey)
    }

    /// "End all": every session this window commanded is ended, whether or
    /// not it is still mid-turn — ending the stuck ones is the button's job.
    func endAll() {
        endSessions(commanded)
        commanded = []
        // The sessions those cards belonged to are gone.
        approvals = []
    }
}
