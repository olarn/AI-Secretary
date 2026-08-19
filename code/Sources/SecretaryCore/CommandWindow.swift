import CoreGraphics
import Foundation

/// The command window's decisions: who a broadcast goes to, what each recipient
/// is told, how dropped instruction files merge, and where the window sits.
///
/// Plain Swift where it crosses into the app target (the same rule as
/// `StatusMenu`), pure everywhere: same text and same roster in, same answer
/// out. The window itself only applies these answers.

// MARK: - Who receives a command

/// What pressing send in the command window should do.
public enum CommandDispatch: Equatable, Sendable {
    /// Nobody is ticked. The red line under the box; nothing is sent.
    case needSelection
    /// The message names only characters that are not ticked. Sending it to
    /// the ticked ones instead would be work handed to someone who was never
    /// asked — the same wrong-recipient hazard `DelegationIntent` records — so
    /// it is refused with the names, and the person ticks them or rephrases.
    case namedNotSelected([String])
    /// Send it to these, each with her own copy.
    case send(to: [CharacterCard])
}

/// Reads the person's command against the ticked characters.
///
/// The rule has one narrowing step: a command that names ticked characters goes
/// only to the named ones ("Miku pin คำตอบล่าสุดไว้" with three ticked runs Miku
/// alone), and a command that names nobody goes to everyone ticked. Matching
/// reuses `namesFor` — the same full-name-or-first-word reading the hand-off
/// path trusts — rather than growing a second, slightly different notion of
/// what counts as naming somebody.
///
/// `roster` is everyone on the desktop, ticked or not: a name that matches the
/// roster but not the selection is how `namedNotSelected` is told apart from
/// prose that names nobody.
public func commandRecipients(
    for text: String,
    selected: [CharacterCard],
    roster: [CharacterCard]
) -> CommandDispatch {
    guard !selected.isEmpty else { return .needSelection }

    let haystack = text.lowercased()
    let named = roster.filter { card in
        namesFor(card).contains { haystack.contains($0) }
    }
    let namedAndSelected = named.filter { card in selected.contains { $0.id == card.id } }

    if !named.isEmpty && namedAndSelected.isEmpty {
        return .namedNotSelected(named.map(\.name))
    }
    return .send(to: namedAndSelected.isEmpty ? selected : namedAndSelected)
}

/// The red line under the box when nobody is ticked. In the product's own
/// words — the backlog states this string, not just that one exists.
public let selectAtLeastOneCharacterMessage = "เลือกอย่างน้อย 1 ตัว"

/// The red line when the command names only characters that are not ticked.
public func namedNotSelectedMessage(_ names: [String]) -> String {
    "\(names.joined(separator: ", ")) ไม่ได้ถูกเลือก — เลือกก่อน หรือแก้คำสั่ง"
}

// MARK: - What each recipient is told

/// One recipient's copy of a broadcast.
///
/// Sent to one character, the instructions go as typed — it is the same act as
/// typing in her own chat, and a preamble would be noise. Sent to several, each
/// copy opens by saying who else received it and how shared work is divided:
/// by name or role when the instructions assign it, among themselves when they
/// don't. The characters already reach each other through their own hand-off
/// blocks, so "divide it yourselves" is something they can actually do.
public func commandMessage(
    for recipient: CharacterCard,
    among recipients: [CharacterCard],
    instructions: String
) -> String {
    guard recipients.count > 1 else { return instructions }
    let others = recipients.filter { $0.id != recipient.id }.map(\.name).joined(separator: ", ")
    return """
    [Command window] This instruction was sent to you (\(recipient.name)) and \(others) at the same time. \
    If it assigns work to specific characters by name or by role, do only the parts meant for you and ignore the rest. \
    If it defines roles, remember yours and act by it from now on. \
    If work is left unassigned, divide it among yourselves — take a fair share and hand the rest off to the others.

    \(instructions)
    """
}

// MARK: - Instruction files

/// Dropped instruction files and the typed text, merged into one instruction.
///
/// In drop order — the backlog's rule is that steps in the first file run
/// before steps in the next — with the typed text last, since it is written
/// with the files already on the window and reads as a note about them.
public func mergedInstructions(files: [String], typed: String) -> String {
    let parts = (files + [typed])
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return parts.joined(separator: "\n\n")
}

// MARK: - Where the window sits

/// The one place the defaults key is written, so save and load can't drift.
public let commandWindowOriginKey = "commandWindow.origin"

/// The saved origin, in the only form `UserDefaults` round-trips exactly.
public func commandWindowOriginString(_ origin: CGPoint) -> String {
    "\(origin.x),\(origin.y)"
}

/// Where the window opens: the remembered spot, or the middle of the screen.
///
/// Clamped to the visible frame either way — a position saved on a display
/// that is no longer attached would otherwise open the window somewhere no
/// click can reach.
public func commandWindowOrigin(
    saved: String?,
    size: CGSize,
    visibleFrame: CGRect
) -> CGPoint {
    let centre = CGPoint(
        x: visibleFrame.midX - size.width / 2,
        y: visibleFrame.midY - size.height / 2
    )
    let parsed = saved
        .map { $0.split(separator: ",").compactMap { Double($0) } }
        .flatMap { parts in parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil }
    let wanted = parsed ?? centre
    return CGPoint(
        x: min(max(wanted.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width)),
        y: min(max(wanted.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))
    )
}

// MARK: - How wide it is

/// The one place these defaults keys are written, same rule as the origin's.
public let commandWindowWidthKey = "commandWindow.width"
/// Height granted beyond the minimum, all of it the message box's — the
/// window's own height is never stored, because the minimum moves with the
/// content and a stored total would reopen with yesterday's error line's
/// worth of dead space.
public let commandWindowExtraHeightKey = "commandWindow.extraHeight"

/// Asked for by the owner (2026-08-19): the window resizes. Width only — the
/// height always follows the content, so a free height would either clip the
/// box or leave dead slab under it.
public let commandWindowDefaultWidth: Double = 620

/// Narrow enough to park beside other work, never so narrow the chips wrap
/// into a column; wide enough for a long instruction, never wider than the
/// smallest screen this app targets.
public func commandWindowWidth(saved: Double?) -> Double {
    guard let saved, saved > 0 else { return commandWindowDefaultWidth }
    return min(max(saved, 380), 1000)
}

// MARK: - The menu row

/// One row for both directions, worded from what is on screen right now —
/// the same rule as `allCharactersTitle`, for the same reason.
public func commandWindowMenuTitle(isVisible: Bool) -> String {
    isVisible ? "Hide Command" : "Show Command"
}
