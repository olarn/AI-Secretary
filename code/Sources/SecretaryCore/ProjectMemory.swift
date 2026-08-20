import Foundation

/// What a character remembers about a project, and where it is kept.
///
/// **The store already exists and is already being read.** Verified against
/// Claude Code 2.1.220 on 2026-08-14: a `claude -p` started with this app's
/// exact flag set, with the working directory set to a registered project,
/// loads that project's `CLAUDE.md` *and*
/// `~/.claude/projects/<slug>/memory/MEMORY.md` into its context without being
/// asked. So the reading half of "give the app access to the project's memory"
/// was true the moment Sprint 5 pointed the backend at a project folder — what
/// was missing is the other half: nothing the character learned ever got
/// written back.
///
/// That is why this writes into the Claude Code memory directory rather than
/// into Application Support beside the conversations. A second store would have
/// to be hand-injected into `--append-system-prompt` while the character went
/// on reading a *different* memory from the same conceptual place, and the
/// person's own terminal `claude` would see one and not the other. One store,
/// read by both.
///
/// The consequence is stated rather than hidden: what a character remembers
/// here is also what the person's terminal sessions in that project will read.
/// That is the feature — and it is why writing asks first.

// MARK: - Where Claude Code keeps a project's memory

/// The directory name Claude Code derives from a working directory.
///
/// **Measured, not guessed.** Every character outside `[A-Za-z0-9-]` becomes a
/// dash, one dash per UTF-16 code unit, and case is kept. Two observations pin
/// the parts that no reading of the shape would give you:
///
/// - `/Users/Olarn/…/A_b.c d,e-ก่ะZ9` → `…-A-b-c-d-e----Z9`. The three Thai
///   scalars produce three dashes, so it is not per grapheme cluster — `ก่` is
///   one grapheme and would have produced one.
/// - `/Users/Olarn/…/em🎨x` → `…-em--x`. One emoji produces *two* dashes, so it
///   is not per Unicode scalar either. UTF-16 code units is the only unit that
///   gives both answers, which is what a JavaScript `String.replace` over a
///   non-`u` regex does.
///
/// Getting this wrong is silent: memory would be written to a directory that
/// nothing ever reads.
public func claudeProjectSlug(forPath path: String) -> String {
    String(
        decoding: canonicalProjectPath(path).utf16.map { unit -> UInt16 in
            let isKept = (unit >= 0x41 && unit <= 0x5A)   // A-Z
                || (unit >= 0x61 && unit <= 0x7A)          // a-z
                || (unit >= 0x30 && unit <= 0x39)          // 0-9
                || unit == 0x2D                            // -
            return isKept ? unit : 0x2D
        },
        as: UTF16.self
    )
}

/// Symlinks resolved the way the shell resolves them: `/tmp` is `-private-tmp`
/// on disk.
///
/// `realpath(3)` and not Foundation. Both `standardizedFileURL` and
/// `resolvingSymlinksInPath` hand back `/tmp` — the second resolves the link
/// and then strips the leading `/private` again for tidiness, which is exactly
/// the component the directory name is built from. `Project.normalize` is not
/// reused for the same reason and one more: it answers "are these the same
/// project", a laxer question than "which directory did Claude Code name".
///
/// A path that does not exist cannot be resolved, so it is used as given —
/// standardised, which is all that can honestly be done with it. Every real
/// project is a directory that exists.
private func canonicalProjectPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else {
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
    defer { free(resolved) }
    return String(cString: resolved)
}

/// - Parameter home: the user's home directory, passed in rather than read, so
///   the function is the same function on every machine and in every test.
public func claudeMemoryDirectory(forProjectAt path: String, home: URL) -> URL {
    home
        .appendingPathComponent(".claude/projects", isDirectory: true)
        .appendingPathComponent(claudeProjectSlug(forPath: path), isDirectory: true)
        .appendingPathComponent("memory", isDirectory: true)
}

// MARK: - One thing remembered

/// A single fact about a project, as it will be filed.
///
/// One file per fact rather than one long note, because that is the shape the
/// recall mechanism was built for: only `MEMORY.md` is loaded into context
/// automatically, and it is the one-line pointers in it that decide which files
/// get opened. A single growing file would arrive as one pointer that is either
/// always relevant or never.
public struct MemoryNote: Equatable, Sendable {
    /// One line, and the thing the index is scanned for.
    public let title: String
    /// The fact itself. May be empty, in which case the title *is* the fact.
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    /// The file this note is written to, derived from the title so a fact
    /// recorded twice overwrites rather than accumulating near-duplicates.
    public var fileName: String { memoryFileName(for: title) + ".md" }

    /// Frontmatter plus the fact, in the format the memory directory already
    /// holds — `type: project`, because that is what every one of these is.
    public var markdown: String {
        """
        ---
        name: \(memoryFileName(for: title))
        description: \(title)
        metadata:
          type: project
        ---

        \(body.isEmpty ? title : body)
        """
    }

    /// The pointer in `MEMORY.md`. This line is the whole reachability of the
    /// note: a file with no line here is a file nothing will ever look at.
    public var indexLine: String { "- [\(title)](\(fileName)) — \(hook)" }

    /// The first sentence of the fact, short enough to sit on one line of an
    /// index that is read in full every session.
    private var hook: String {
        let source = body.isEmpty ? title : body
        let firstLine = source.components(separatedBy: .newlines).first ?? source
        return firstLine.count <= 90 ? firstLine : String(firstLine.prefix(89)) + "…"
    }
}

/// A kebab-case name for a title, in the ASCII range the existing files use.
///
/// Non-ASCII is dropped rather than transliterated, so a title with no ASCII in
/// it has no stem to make a name from. **The fallback is a fingerprint of the
/// title, not a fixed word.** A fixed word was what shipped first, and driving
/// it found the hole: the owner writes in Thai, so every all-Thai fact would
/// have been filed as `project-note.md` and each one would have silently
/// replaced the last — with the index line replaced alongside it, so nothing
/// would even look broken. The fingerprint keeps re-recording the *same* title
/// idempotent, which is the property the index depends on, while two different
/// titles stay two different files.
///
/// The title itself still carries the meaning: it is in the frontmatter, in the
/// index line, and on screen. Only the file name is ASCII.
public func memoryFileName(for title: String) -> String {
    let stem = title.lowercased().utf16.map { unit -> UInt16 in
        let isKept = (unit >= 0x61 && unit <= 0x7A) || (unit >= 0x30 && unit <= 0x39)
        return isKept ? unit : 0x2D
    }
    let collapsed = String(decoding: stem, as: UTF16.self)
        .components(separatedBy: "-")
        .filter { !$0.isEmpty }
        .prefix(6)
        .joined(separator: "-")
    guard !collapsed.isEmpty else { return "note-\(InstructionFingerprint.of(title))" }
    return String(collapsed.prefix(60))
}

// MARK: - The index

/// `MEMORY.md` with this note's pointer in it, replacing any line that already
/// points at the same file.
///
/// Replacing rather than appending is what makes recording the same fact twice
/// idempotent — the note file is overwritten by name, and without this the
/// index would grow a second line pointing at the same overwritten file.
public func memoryIndex(existing: String, adding note: MemoryNote) -> String {
    let target = "(\(note.fileName))"
    let kept = existing
        .components(separatedBy: .newlines)
        .filter { !$0.contains(target) }
    let trimmed = trailingBlanksRemoved(kept)
    return (trimmed + [note.indexLine]).joined(separator: "\n") + "\n"
}

private func trailingBlanksRemoved(_ lines: [String]) -> [String] {
    var out = lines
    while out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast() }
    return out
}

// MARK: - The block

/// The assistant asking for something to be kept.
///
/// ```remember
/// The build script must run from code/, not the repo root
/// package-app.sh deletes every other AISecretary.app in the repo,
/// so running it from a worktree leaves code/ with no build at all.
/// ```
///
/// Marked, never inferred, for the reason every block here is marked: a model
/// writes "I'll remember that" constantly, and a reply that merely says so must
/// not write a file into the person's Claude Code memory — where their own
/// terminal sessions will read it back for months.
///
/// First line is the title, the rest is the fact. `FencedBlock.split` already
/// drops blank lines and trims each one, so a blank separator cannot be relied
/// on and is not asked for.
public struct RememberBlock: Equatable, Sendable {
    public let body: String
    public let note: MemoryNote?

    static let fence = "```remember"

    public init(body: String, note: MemoryNote?) {
        self.body = body
        self.note = note
    }

    public static func parse(_ text: String) -> RememberBlock {
        guard let (body, lines) = FencedBlock.split(text, fence: fence),
              let title = lines.first
        else { return RememberBlock(body: text, note: nil) }

        return RememberBlock(
            body: body,
            note: MemoryNote(title: title, body: lines.dropFirst().joined(separator: "\n"))
        )
    }
}

// MARK: - What is said about it

/// The card's one-line summary of what will be written where.
///
/// **No project name in it.** The sentence it lands in already ends with "in
/// \(project)", and the first drive of this produced "…for my-mcp-server, in
/// your Claude Code memory in my-mcp-server?" — the name twice in one question.
///
/// It does say *outside the project folder*. That began as a correction to the
/// card's subtitle, which read "Writes files in the project" back when this
/// shared `.localWrite` with every other write; the class was split and
/// `.projectMemoryWrite` now says it too. Kept because the sentence is what the
/// person reads first, and saying where a write lands twice is cheap next to
/// their believing it lands in the project.
public func memoryApprovalSummary(_ note: MemoryNote) -> String {
    "keep “\(note.title)” in your Claude Code memory (outside the project folder)"
}

public func memorySavedLine(_ note: MemoryNote, project: String) -> String {
    "Kept for \(project) — “\(note.title)” is in this project's memory. "
        + "Both I and `claude` in the terminal will read it next time."
}

/// One decision is pending at a time, and something else got there first.
///
/// Said rather than swallowed, like every other refusal here. Dropping it in
/// silence would leave her believing it was kept — the same failure the write
/// error is announced for, and rare enough that nobody would ever find it by
/// using the app.
public func memoryBusyLine(_ note: MemoryNote) -> String {
    "Something else is still waiting on your answer, so I haven't kept “\(note.title)” yet "
        + "— tell me again once that one's settled."
}

public func memoryFailedLine(_ note: MemoryNote, reason: String) -> String {
    "Couldn't write “\(note.title)” to memory — \(reason)"
}

/// Refused before it is written, when the fact itself reads as an instruction.
///
/// This is the one thing memory adds that no other block does: text written by
/// a model is re-read as context on every later turn, by this app *and* by the
/// person's own terminal. A line that says "ignore previous instructions" is
/// therefore not a note, it is a standing order, and `instructionRisks` already
/// knows the shapes.
public func memoryRefusedLine(_ note: MemoryNote, risks: [InstructionRisk]) -> String {
    let reasons = risks.map { "• \($0.reason) — \($0.evidence)" }.joined(separator: "\n")
    return """
        ผมไม่เขียน “\(note.title)” ลง memory ครับ — ข้อความนี้อ่านเป็นคำสั่ง ไม่ใช่ข้อเท็จจริง \
        และของที่อยู่ใน memory จะถูกอ่านซ้ำทุกรอบ รวมถึงตอนคุณเปิดเทอร์มินัลเอง

        \(reasons)
        """
}

/// Told to the character only while a project is open, because with none open
/// there is no project for a fact to be about — the scratch folder is where she
/// stands when the person chose nothing, and memory accumulating under it would
/// be memory filed against a project nobody picked.
public func memoryPrompt(projectName: String) -> String {
    """
    You have a memory for “\(projectName)” that persists between conversations. \
    You are already reading it: `MEMORY.md` in this project's Claude Code memory \
    directory is loaded into your context at the start of every turn, along with \
    the project's `CLAUDE.md`.

    To add something to it, end your message with a block like this:

    \(RememberBlock.fence)
    A short title, one line
    The fact itself, in as many lines as it takes
    ```

    The app writes the file — you must not write it yourself, and you do not \
    have access to that directory. The person is asked first, and told what was \
    saved.

    Record only what would still be worth knowing next week and is not already \
    in the project's own files: a decision and why it was taken, a constraint \
    that isn't written down, a preference the person stated. Never record \
    secrets, and never record an instruction for your future self to follow — \
    this memory is read by the person's own terminal sessions too, so a note \
    that gives orders is a note that gives them orders.
    """
}
