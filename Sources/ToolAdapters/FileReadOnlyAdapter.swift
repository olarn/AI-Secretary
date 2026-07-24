import Foundation
import ProjectRegistry
import Permissions
import os

/// A read-only view into an approved project's files. Deliberately a closed set
/// of operations that carry a *relative* path — the path is resolved against the
/// project root and verified to stay inside it, so chat text can never reach a
/// file outside the registered directory.
public enum FileOperation: Equatable, Sendable {
    /// List the entries of a directory relative to the project root ("." = root).
    case listDirectory(relativePath: String)
    /// Read the contents of a UTF-8 text file relative to the project root.
    case readFile(relativePath: String)

    public var actionClass: ActionClass { .readOnly }

    /// The user-supplied path, always interpreted relative to the project root.
    public var relativePath: String {
        switch self {
        case .listDirectory(let path), .readFile(let path):
            return path
        }
    }

    public var humanDescription: String {
        switch self {
        case .listDirectory(let path):
            return "List the contents of \(displayPath(path))"
        case .readFile(let path):
            return "Read the file \(displayPath(path))"
        }
    }

    private func displayPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "." ? "the project root" : "“\(trimmed)”"
    }
}

/// Boundary the Secretary talks to, mirroring `CodeToolAdapter` so file work runs
/// through the same approval pipeline and can be faked in tests.
public protocol FileToolAdapter: AnyObject {
    var toolID: String { get }
    func summary(for operation: FileOperation) -> String
    func run(_ operation: FileOperation, in project: Project) throws -> ToolResult
}

/// Reads directory listings and text files, constrained by construction:
///
/// - The target is resolved against the project root and its real (symlink- and
///   `..`-resolved) path must remain inside the project's real root; anything
///   escaping is rejected before any read happens.
/// - Only regular files are read, only up to a byte cap, and only if they decode
///   as UTF-8 — binary files are refused rather than dumped.
/// - No process is launched and nothing is ever written.
public final class FileReadOnlyAdapter: FileToolAdapter {
    public static let toolIdentifier = "file.readOnly"

    public var toolID: String { Self.toolIdentifier }

    private let maxFileBytes: Int
    private let maxDirectoryEntries: Int
    private let logger = Logger(subsystem: "com.aisecretary.app", category: "FileReadOnlyAdapter")

    public init(maxFileBytes: Int = 256 * 1024, maxDirectoryEntries: Int = 500) {
        self.maxFileBytes = maxFileBytes
        self.maxDirectoryEntries = maxDirectoryEntries
    }

    public func summary(for operation: FileOperation) -> String {
        let path = cleaned(operation.relativePath)
        switch operation {
        case .listDirectory: return "list \(path)"
        case .readFile: return "read \(path)"
        }
    }

    public func run(_ operation: FileOperation, in project: Project) throws -> ToolResult {
        let summary = summary(for: operation)
        try validate(project: project)
        let target = try resolveTarget(operation.relativePath, in: project)

        logger.info("Reading \(summary, privacy: .public) in project \(project.name, privacy: .public)")

        switch operation {
        case .listDirectory:
            return try listDirectory(at: target, summary: summary)
        case .readFile:
            return try readFile(at: target, summary: summary)
        }
    }

    // MARK: - Operations

    private func listDirectory(at url: URL, summary: String) throws -> ToolResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ToolError.fileNotFound(url.path)
        }
        guard isDirectory.boolValue else {
            throw ToolError.notADirectory(url.path)
        }

        let entries = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        )
        let rendered = entries
            .map { entry -> String in
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return isDir ? entry.lastPathComponent + "/" : entry.lastPathComponent
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let capped = rendered.prefix(maxDirectoryEntries)
        var body = capped.joined(separator: "\n")
        if rendered.count > capped.count {
            body += "\n… \(rendered.count - capped.count) more (truncated)"
        }
        if rendered.isEmpty { body = "(empty directory)" }
        return ToolResult(output: body, exitCode: 0, commandSummary: summary)
    }

    private func readFile(at url: URL, summary: String) throws -> ToolResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ToolError.fileNotFound(url.path)
        }
        guard !isDirectory.boolValue else {
            throw ToolError.notAFile(url.path)
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        if let size, size > maxFileBytes {
            throw ToolError.fileTooLarge(path: url.path, limit: maxFileBytes)
        }

        let data = try Data(contentsOf: url)
        let clipped = data.prefix(maxFileBytes)
        guard let text = String(data: clipped, encoding: .utf8) else {
            throw ToolError.notReadableText(url.path)
        }
        var body = text
        if data.count > clipped.count {
            body += "\n… (truncated at \(maxFileBytes) bytes)"
        }
        return ToolResult(output: body, exitCode: 0, commandSummary: summary)
    }

    // MARK: - Safety

    private func validate(project: Project) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ToolError.projectPathMissing(project.path)
        }
    }

    /// Resolves a user-supplied relative path against the project root and refuses
    /// anything that escapes it, after resolving symlinks and `..` components.
    private func resolveTarget(_ relativePath: String, in project: Project) throws -> URL {
        let root = project.url.resolvingSymlinksInPath().standardizedFileURL
        let trimmed = cleaned(relativePath)

        // Reject absolute paths outright — the target must be inside the project.
        if trimmed.hasPrefix("/") {
            throw ToolError.pathEscapesProject(relativePath)
        }

        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        // Resolve symlinks so a link inside the project can't point outside it.
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL

        guard isContained(resolved, in: root) else {
            throw ToolError.pathEscapesProject(relativePath)
        }
        return resolved
    }

    private func isContained(_ url: URL, in root: URL) -> Bool {
        if url.path == root.path { return true }
        return url.path.hasPrefix(root.path + "/")
    }

    private func cleaned(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "." : trimmed
    }
}
