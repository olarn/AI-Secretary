import FunctionalCore
import Foundation

/// Writing a note into the Claude Code memory directory for a project.
///
/// Everything that decides anything is in `ProjectMemory.swift`; this only
/// touches the disk. It is a value with a `home` rather than a reader of
/// `FileManager.default.homeDirectory`, so a test writes into a temporary
/// directory and asserts the bytes, and so the pure half never learns where
/// home is.
///
/// **The app writes, not the model.** That is what keeps this from widening any
/// tool grant: the memory directory is outside every registered project and is
/// never passed to `--add-dir`, so nothing the backend can reach has changed.
/// The character asks with a ```remember block; the app is what puts bytes on
/// disk, after the person has said yes.
public struct FileProjectMemoryStore: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// The note file and the index line, both, or a reason.
    ///
    /// Both or neither is not achievable without a transaction the filesystem
    /// does not offer, so the order is chosen instead: the note file first, the
    /// index second. A note with no index line is invisible and harmless; an
    /// index line pointing at a file that was never written is a dangling
    /// pointer in the one document that is read every session.
    public func save(_ note: MemoryNote, forProjectAt path: String) -> Either<String, URL> {
        let directory = claudeMemoryDirectory(forProjectAt: path, home: home)
        let noteURL = directory.appendingPathComponent(note.fileName)
        let indexURL = directory.appendingPathComponent("MEMORY.md")

        return attempt {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(note.markdown.utf8).write(to: noteURL, options: .atomic)
            let existing = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
            try Data(memoryIndex(existing: existing, adding: note).utf8)
                .write(to: indexURL, options: .atomic)
            return noteURL
        }
        .mapLeft { $0.localizedDescription }^
    }
}
