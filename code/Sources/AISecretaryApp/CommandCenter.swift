import Foundation
import SecretaryCore

/// One instruction file dropped on the command window, already read: the drop
/// is the moment the file exists for sure, and holding text rather than a URL
/// means nothing re-reads the disk at send time.
struct DroppedInstruction: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let text: String
}

/// What the command window is holding: who is ticked, which files are waiting,
/// and who has been commanded — the set "จบการทำงาน" acts on.
///
/// Gathering and applying only. Every decision — who a command reaches, what
/// each copy says, how files merge — is a pure function in `SecretaryCore`,
/// because this target is never linked into the test bundle.
@MainActor
@Observable
final class CommandCenter {
    /// Everyone on the desktop, asked for rather than held — the same rule as
    /// `CharacterBus`, so a character added or deleted needs nothing rewired.
    @ObservationIgnored let roster: () -> [CharacterCard]
    /// Hands one character her copy of the command.
    @ObservationIgnored let deliver: (UUID, String) -> Void
    /// Ends the sessions of everyone in the set.
    @ObservationIgnored let endSessions: (Set<UUID>) -> Void

    /// Who is ticked. Commands only ever reach ticked characters; the set can
    /// change at any time and takes effect on the next send.
    var selected: Set<UUID> = []
    /// The red line under the box, when there is one.
    var errorText: String?
    /// Instruction files waiting to go with the next send, in drop order —
    /// the order they merge in.
    var droppedFiles: [DroppedInstruction] = []
    /// Everyone this window has sent a command to since the last
    /// "จบการทำงาน". Hiding the window does not touch it — hiding keeps
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

    init(
        roster: @escaping () -> [CharacterCard],
        deliver: @escaping (UUID, String) -> Void,
        endSessions: @escaping (Set<UUID>) -> Void
    ) {
        self.roster = roster
        self.deliver = deliver
        self.endSessions = endSessions
    }

    func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        // The line said "tick somebody"; they just did. Leaving it up would
        // scold a state that no longer exists.
        errorText = nil
    }

    func attach(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            errorText = "อ่านไฟล์ \(url.lastPathComponent) ไม่ได้"
            return
        }
        droppedFiles.append(DroppedInstruction(name: url.lastPathComponent, text: text))
        errorText = nil
    }

    func detach(_ id: UUID) {
        droppedFiles.removeAll { $0.id == id }
    }

    /// Sends the typed text and the waiting files. Returns whether they went,
    /// which is what tells the view to clear the draft.
    func send(_ typed: String) -> Bool {
        let cards = roster()
        let text = mergedInstructions(files: droppedFiles.map(\.text), typed: typed)
        guard !text.isEmpty else { return false }

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
            recipients.forEach { recipient in
                deliver(recipient.id, commandMessage(for: recipient, among: recipients, instructions: text))
            }
            commanded.formUnion(recipients.map(\.id))
            droppedFiles = []
            errorText = nil
            return true
        }
    }

    /// "จบการทำงาน": every session this window commanded is ended, whether or
    /// not it is still mid-turn — ending the stuck ones is the button's job.
    func endAll() {
        endSessions(commanded)
        commanded = []
    }
}
