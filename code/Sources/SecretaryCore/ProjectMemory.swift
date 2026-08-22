import Foundation

public func claudeProjectSlug(forPath path: String) -> String {
    String(
        decoding: canonicalProjectPath(path).utf16.map { unit -> UInt16 in
            isKeptInAClaudeProjectSlug(unit) ? unit : dashUTF16
        },
        as: UTF16.self
    )
}

private let dashUTF16: UInt16 = 0x2D

private func isUppercaseLetter(_ utf16Unit: UInt16) -> Bool { utf16Unit >= 0x41 && utf16Unit <= 0x5A }

private func isLowercaseLetter(_ utf16Unit: UInt16) -> Bool { utf16Unit >= 0x61 && utf16Unit <= 0x7A }

private func isDigit(_ utf16Unit: UInt16) -> Bool { utf16Unit >= 0x30 && utf16Unit <= 0x39 }

private func isKeptInAClaudeProjectSlug(_ utf16Unit: UInt16) -> Bool {
    isUppercaseLetter(utf16Unit)
        || isLowercaseLetter(utf16Unit)
        || isDigit(utf16Unit)
        || utf16Unit == dashUTF16
}

private func isKeptInAMemoryFileNameStem(_ utf16Unit: UInt16) -> Bool {
    isLowercaseLetter(utf16Unit) || isDigit(utf16Unit)
}

private func canonicalProjectPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else {
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
    defer { free(resolved) }
    return String(cString: resolved)
}

public func claudeMemoryDirectory(forProjectAt path: String, home: URL) -> URL {
    home
        .appendingPathComponent(".claude/projects", isDirectory: true)
        .appendingPathComponent(claudeProjectSlug(forPath: path), isDirectory: true)
        .appendingPathComponent("memory", isDirectory: true)
}

public struct MemoryNote: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    public var fileName: String { memoryFileName(for: title) + ".md" }

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

    public var indexLine: String { "- [\(title)](\(fileName)) — \(hook)" }

    private var hook: String {
        let source = body.isEmpty ? title : body
        let firstLine = source.components(separatedBy: .newlines).first ?? source
        return firstLine.count <= 90 ? firstLine : String(firstLine.prefix(89)) + "…"
    }
}

public func memoryFileName(for title: String) -> String {
    let stem = title.lowercased().utf16.map { unit -> UInt16 in
        isKeptInAMemoryFileNameStem(unit) ? unit : dashUTF16
    }
    let collapsed = String(decoding: stem, as: UTF16.self)
        .components(separatedBy: "-")
        .filter { !$0.isEmpty }
        .prefix(6)
        .joined(separator: "-")
    guard !collapsed.isEmpty else { return "note-\(InstructionFingerprint.of(title))" }
    return String(collapsed.prefix(60))
}

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

public func memoryApprovalSummary(_ note: MemoryNote) -> String {
    "keep “\(note.title)” in your Claude Code memory (outside the project folder)"
}

public func memorySavedLine(_ note: MemoryNote, project: String) -> String {
    "Kept for \(project) — “\(note.title)” is in this project's memory. "
        + "Both I and `claude` in the terminal will read it next time."
}

public func memoryBusyLine(_ note: MemoryNote) -> String {
    "Something else is still waiting on your answer, so I haven't kept “\(note.title)” yet "
        + "— tell me again once that one's settled."
}

public func memoryFailedLine(_ note: MemoryNote, reason: String) -> String {
    "Couldn't write “\(note.title)” to memory — \(reason)"
}

public func memoryRefusedLine(_ note: MemoryNote, risks: [InstructionRisk]) -> String {
    let reasons = risks.map { "• \($0.reason) — \($0.evidence)" }.joined(separator: "\n")
    return """
        ผมไม่เขียน “\(note.title)” ลง memory ครับ — ข้อความนี้อ่านเป็นคำสั่ง ไม่ใช่ข้อเท็จจริง \
        และของที่อยู่ใน memory จะถูกอ่านซ้ำทุกรอบ รวมถึงตอนคุณเปิดเทอร์มินัลเอง

        \(reasons)
        """
}

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
