import FunctionalCore
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
    func run(_ operation: FileOperation, in project: Project) -> Either<ToolError, ToolResult>
}

/// Reads directory listings and text files, constrained by construction:
///
/// - The target is resolved against the project root and its real (symlink- and
///   `..`-resolved) path must remain inside the project's real root; anything
///   escaping is rejected before any read happens.
/// - Only regular files are read, only up to a byte cap, and only if they decode
///   as UTF-8 — binary files are refused rather than dumped.
/// - No process is launched and nothing is ever written.
///
/// Each of those guarantees is one rail below. They run in order and the first
/// refusal short-circuits, so a read cannot happen unless every check passed.
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
        let path = cleanedPath(operation.relativePath)
        switch operation {
        case .listDirectory: return "list \(path)"
        case .readFile: return "read \(path)"
        }
    }

    public func run(_ operation: FileOperation, in project: Project) -> Either<ToolError, ToolResult> {
        let summary = summary(for: operation)

        return requireProjectDirectory(project)
            .flatMap { _ in self.resolveTarget(operation.relativePath, in: project) }^
            .flatMap { target in
                self.logger.info(
                    "Reading \(summary, privacy: .public) in project \(project.name, privacy: .public)"
                )
                return self.perform(operation, at: target, summary: summary)
            }^
    }

    private func perform(
        _ operation: FileOperation,
        at target: URL,
        summary: String
    ) -> Either<ToolError, ToolResult> {
        switch operation {
        case .listDirectory:
            return listDirectory(at: target, summary: summary)
        case .readFile:
            return readFile(at: target, summary: summary)
        }
    }

    // MARK: - Operations

    private func listDirectory(at url: URL, summary: String) -> Either<ToolError, ToolResult> {
        requireDirectory(at: url)
            .flatMap { _ in
                attempt {
                    try FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsSubdirectoryDescendants]
                    )
                }
                .mapLeft { ToolError.launchFailed($0.localizedDescription) }^
            }^
            .map { entries in
                ToolResult(
                    output: self.render(entries),
                    exitCode: 0,
                    commandSummary: summary
                )
            }^
    }

    private func render(_ entries: [URL]) -> String {
        let names = entries
            .map { entry -> String in
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return isDir ? entry.lastPathComponent + "/" : entry.lastPathComponent
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        guard !names.isEmpty else { return "(empty directory)" }

        let capped = names.prefix(maxDirectoryEntries)
        let body = capped.joined(separator: "\n")
        return names.count > capped.count
            ? body + "\n… \(names.count - capped.count) more (truncated)"
            : body
    }

    private func readFile(at url: URL, summary: String) -> Either<ToolError, ToolResult> {
        requireRegularFile(at: url)
            .flatMap { _ in self.requireWithinSizeLimit(at: url) }^
            .flatMap { _ in
                attempt { try Data(contentsOf: url) }
                    .mapLeft { _ in ToolError.fileNotFound(url.path) }^
            }^
            .flatMap { data in self.decodeText(data, at: url) }^
            .map { ToolResult(output: $0, exitCode: 0, commandSummary: summary) }^
    }

    private func decodeText(_ data: Data, at url: URL) -> Either<ToolError, String> {
        let clipped = data.prefix(maxFileBytes)
        return Option.fromOptional(String(data: clipped, encoding: .utf8))
            .fold(
                { .left(.notReadableText(url.path)) },
                { text in
                    .right(
                        data.count > clipped.count
                            ? text + "\n… (truncated at \(self.maxFileBytes) bytes)"
                            : text
                    )
                }
            )
    }

    // MARK: - Safety rails

    private func requireProjectDirectory(_ project: Project) -> Either<ToolError, Project> {
        isDirectory(atPath: project.path)
            ? .right(project)
            : .left(.projectPathMissing(project.path))
    }

    private func requireDirectory(at url: URL) -> Either<ToolError, URL> {
        guard exists(atPath: url.path) else { return .left(.fileNotFound(url.path)) }
        return isDirectory(atPath: url.path) ? .right(url) : .left(.notADirectory(url.path))
    }

    private func requireRegularFile(at url: URL) -> Either<ToolError, URL> {
        guard exists(atPath: url.path) else { return .left(.fileNotFound(url.path)) }
        return isDirectory(atPath: url.path) ? .left(.notAFile(url.path)) : .right(url)
    }

    private func requireWithinSizeLimit(at url: URL) -> Either<ToolError, URL> {
        let size = Option.fromOptional(
            try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        ).flatMap { Option.fromOptional($0) }^

        let limit = maxFileBytes
        return size.filter { $0 > limit }^.isDefined
            ? .left(.fileTooLarge(path: url.path, limit: limit))
            : .right(url)
    }

    /// Resolves a user-supplied relative path against the project root and refuses
    /// anything that escapes it, after resolving symlinks and `..` components.
    private func resolveTarget(
        _ relativePath: String,
        in project: Project
    ) -> Either<ToolError, URL> {
        let root = project.url.resolvingSymlinksInPath().standardizedFileURL
        let trimmed = cleanedPath(relativePath)

        // Reject absolute paths outright — the target must be inside the project.
        guard !trimmed.hasPrefix("/") else { return .left(.pathEscapesProject(relativePath)) }

        // Resolve symlinks so a link inside the project can't point outside it.
        let resolved = root
            .appendingPathComponent(trimmed)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL

        return isContained(resolved, in: root)
            ? .right(resolved)
            : .left(.pathEscapesProject(relativePath))
    }

    private func isContained(_ url: URL, in root: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path + "/")
    }

    private func exists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return found && isDirectory.boolValue
    }
}

/// Blank means "the project root". Free function because both the adapter and
/// its summary need it and neither owns it.
func cleanedPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "." : trimmed
}
