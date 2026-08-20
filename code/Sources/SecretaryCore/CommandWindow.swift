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
public let selectAtLeastOneCharacterMessage = "Tick at least one character"

/// The red line when the command names only characters that are not ticked.
public func namedNotSelectedMessage(_ names: [String]) -> String {
    "\(names.joined(separator: ", ")) not ticked — tick them, or reword the command"
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

// MARK: - What a dropped file becomes

/// What one file dragged onto the command window turns into.
public enum CommandDropRole: Equatable, Sendable {
    /// Read as text and merged into the instructions.
    case instruction
    /// Handed to each recipient as a real attachment, the way the chat's own
    /// drop does — an image read as UTF-8 was an error message before this.
    case attachment
}

/// Notes are instructions; everything else rides along as a file. Extension
/// rather than content sniffing, because "a markdown file of tasks" versus "a
/// CSV the tasks are about" is a distinction of kind, not of bytes.
public func commandDropRole(forExtension ext: String) -> CommandDropRole {
    ["md", "markdown", "txt", "text"].contains(ext.lowercased()) ? .instruction : .attachment
}

// MARK: - The box's own text size

/// The one place this defaults key is written, same rule as the origin's.
public let commandFontSizeKey = "commandWindow.fontSize"

/// The chat boxes' default, which is where this box's look came from.
public let commandWindowDefaultFontSize: Double = 13

/// ⌘+ / ⌘− while the command box holds the caret size *this box*, not the
/// focused character's chat — the window is the app's, and growing one
/// character's bubbles because the pointer happened to be here would be the
/// same borrowed-look bug Token Usage exists to avoid. Clamped to the range
/// the chat's own sizes span.
public func clampedCommandFontSize(_ size: Double) -> Double {
    min(max(size, 10), 28)
}

// MARK: - The menu row

/// One row for both directions, worded from what is on screen right now —
/// the same rule as `allCharactersTitle`, for the same reason.
public func commandWindowMenuTitle(isVisible: Bool) -> String {
    isVisible ? "Hide Command" : "Show Command"
}

// MARK: - Saving what came back

/// One answer, as the saved document holds it.
///
/// A value of its own rather than the strip's own row type: `CommandResult`
/// lives in `AISecretaryApp`, which is never linked into the test bundle, and
/// laying out a document is a decision — so it is written and tested here, and
/// the strip only hands over what it is showing.
public struct CommandTranscriptEntry: Equatable, Sendable {
    public let name: String
    public let text: String
    public let succeeded: Bool

    public init(name: String, text: String, succeeded: Bool) {
        self.name = name
        self.text = text
        self.succeeded = succeeded
    }
}

/// What Save writes: the strip as Markdown, in the order it is on screen.
///
/// Screen order, newest first, deliberately — the file is a copy of what the
/// person is looking at, and re-sorting it into "the order it happened" would
/// hand them a document they cannot line up against the window it came from.
///
/// A character who could not finish is marked, because "she answered" and "she
/// failed" read identically once the coloured dot is gone.
public func commandResultsMarkdown(_ entries: [CommandTranscriptEntry]) -> String {
    let body = entries.map { entry -> String in
        let heading = entry.succeeded ? "## \(entry.name)" : "## \(entry.name) — couldn't finish"
        let said = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return said.isEmpty ? heading : "\(heading)\n\n\(said)"
    }
    return (["# Command results"] + body).joined(separator: "\n\n") + "\n"
}

/// The name the save panel opens with. Markdown, because the answers are
/// Markdown — the owner named the default.
public let commandResultsFileName = "command-results.md"
