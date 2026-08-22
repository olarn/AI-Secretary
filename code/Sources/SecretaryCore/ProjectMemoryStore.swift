import FunctionalCore
import Foundation

public struct FileProjectMemoryStore: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

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
