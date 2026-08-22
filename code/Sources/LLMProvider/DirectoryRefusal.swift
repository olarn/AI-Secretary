import Foundation

private let phraseClaudeCodeUsesForTheWorkingDirectoryWall = "allowed working directories"

public func isDirectoryRefusal(_ message: String) -> Bool {
    message.localizedCaseInsensitiveContains(phraseClaudeCodeUsesForTheWorkingDirectoryWall)
}

public func blockedDirectory(tool: String, input: [String: Any], message: String) -> String? {
    if let namedByTheToolItself = directoryFromInput(tool: tool, input: input) {
        return namedByTheToolItself
    }
    return firstQuotedAbsolutePath(in: message)
}

private let toolsWhosePathIsAlreadyADirectory: Set<String> = ["Glob", "Grep", "LS", "NotebookRead"]

private func directoryFromInput(tool: String, input: [String: Any]) -> String? {
    let raw = (input["file_path"] as? String)
        ?? (input["path"] as? String)
        ?? (input["notebook_path"] as? String)
    guard let raw, raw.hasPrefix("/") else { return nil }

    let url = URL(fileURLWithPath: raw).standardizedFileURL
    return toolsWhosePathIsAlreadyADirectory.contains(tool)
        ? url.path
        : url.deletingLastPathComponent().path
}

private func isInsideQuotes(_ componentIndex: Int) -> Bool {
    componentIndex % 2 == 1
}

private func firstQuotedAbsolutePath(in message: String) -> String? {
    let partsSplitOnQuotes = message.components(separatedBy: "'")
    for (index, part) in partsSplitOnQuotes.enumerated() where isInsideQuotes(index) {
        guard part.hasPrefix("/") else { continue }
        let url = URL(fileURLWithPath: part).standardizedFileURL
        let namesAFolderRatherThanAFileInIt = url.pathExtension.isEmpty
        return namesAFolderRatherThanAFileInIt ? url.path : url.deletingLastPathComponent().path
    }
    return nil
}
