import Foundation
import FunctionalCore

import Permissions
import ProjectRegistry
import ToolAdapters

public func watchOnlyProject(at url: URL) -> Project {
    Project(
        name: url.lastPathComponent,
        path: url.path,
        allowedTools: [FileReadOnlyAdapter.toolIdentifier],
        allowedActions: ["read"]
    )
}

public struct WatchRequest: Equatable, Sendable {
    public let relativePath: String

    public init(relativePath: String) {
        self.relativePath = relativePath
    }

    public var displayPath: String {
        let trimmed = relativePath.trimmingCharacters(in: .whitespaces)
        return (trimmed == "." || trimmed == "./") ? "" : trimmed
    }

    public var actionClass: ActionClass { .readOnly }

    public var humanDescription: String {
        "Keep an eye on \(displayPath.isEmpty ? "this project folder" : displayPath) and say when it changes"
    }

    public var absoluteTarget: Option<URL> {
        let trimmed = relativePath.trimmingCharacters(in: .whitespaces)
        let expanded: String
        if trimmed.hasPrefix("/") {
            expanded = trimmed
        } else if trimmed == "~" || trimmed.hasPrefix("~/") {
            expanded = NSString(string: trimmed).expandingTildeInPath
        } else {
            return .none()
        }
        return .some(
            URL(fileURLWithPath: expanded)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .standardizedFileURL
        )
    }
}

public enum WatchChange: Equatable, Sendable {
    case added(String)
    case removed(String)
    case modified(String)

    public var path: String {
        switch self {
        case .added(let path), .removed(let path), .modified(let path): return path
        }
    }
}

public let maxConcurrentWatches = 5

public struct WatchLimits: Equatable, Sendable {
    public let maxEntries: Int
    public let maxDepth: Int
    public let skippedDirectories: Set<String>

    public init(
        maxEntries: Int = 500,
        maxDepth: Int = 4,
        skippedDirectories: Set<String> = [
            ".git", ".build", ".swiftpm", "node_modules", "DerivedData",
            ".venv", "venv", "dist", "Pods", ".next", "target"
        ]
    ) {
        self.maxEntries = maxEntries
        self.maxDepth = maxDepth
        self.skippedDirectories = skippedDirectories
    }
}

public struct WatchSnapshot: Equatable, Sendable {
    public let stamps: [String: String]
    public let wasTruncated: Bool

    public init(stamps: [String: String], wasTruncated: Bool = false) {
        self.stamps = stamps
        self.wasTruncated = wasTruncated
    }

    public var count: Int { stamps.count }

    public func changes(to later: WatchSnapshot) -> [WatchChange] {
        let appeared = later.stamps.compactMap { path, stamp -> WatchChange? in
            guard let before = stamps[path] else { return .added(path) }
            return before == stamp ? nil : .modified(path)
        }
        let gone = stamps.keys
            .filter { later.stamps[$0] == nil }
            .map(WatchChange.removed)

        return (appeared + gone).sorted { $0.path < $1.path }
    }
}

public enum WatchReport {
    static let maxListed = 6

    public static func describe(_ changes: [WatchChange]) -> String {
        guard !changes.isEmpty else { return "no changes" }

        let listed = changes.prefix(maxListed).map { change -> String in
            switch change {
            case .added(let path): return "+ \(path)"
            case .removed(let path): return "− \(path)"
            case .modified(let path): return "~ \(path)"
            }
        }
        let rest = changes.count - listed.count
        let tail = rest > 0 ? "\n…and \(rest) more" : ""
        return listed.joined(separator: "\n") + tail
    }

    public static func headline(_ changes: [WatchChange]) -> String {
        changes.count == 1 ? "1 change" : "\(changes.count) changes"
    }
}

public enum WatchScan {
    static let maxHashedBytes = 1_000_000

    public static func snapshot(
        of target: URL,
        limits: WatchLimits = WatchLimits(),
        fileManager: FileManager = .default
    ) -> WatchSnapshot {
        let url = resolvedRootSoTheListingAndTheRelativePathsAgree(target)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return WatchSnapshot(stamps: [:])
        }

        if !isDirectory.boolValue {
            return WatchSnapshot(stamps: [url.lastPathComponent: fileStamp(url, fileManager: fileManager)])
        }

        var stamps: [String: String] = [:]
        var truncated = false
        var queue: [(url: URL, depth: Int)] = [(url, 0)]

        while !queue.isEmpty {
            let (directory, depth) = queue.removeFirst()
            let contents = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for entry in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if stamps.count >= limits.maxEntries {
                    truncated = true
                    return WatchSnapshot(stamps: stamps, wasTruncated: truncated)
                }
                let name = entry.lastPathComponent
                let entryIsDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false

                if entryIsDirectory {
                    guard !limits.skippedDirectories.contains(name), depth + 1 <= limits.maxDepth else { continue }
                    queue.append((entry, depth + 1))
                } else {
                    guard name != ".DS_Store" else { continue }
                    let resolved = entry.resolvingSymlinksInPath().standardizedFileURL
                    let relative = resolved.path.hasPrefix(url.path + "/")
                        ? String(resolved.path.dropFirst(url.path.count + 1))
                        : resolved.lastPathComponent
                    stamps[relative] = metadataStamp(entry)
                }
            }
        }
        return WatchSnapshot(stamps: stamps, wasTruncated: truncated)
    }

    private static func resolvedRootSoTheListingAndTheRelativePathsAgree(_ target: URL) -> URL {
        target.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func fileStamp(_ url: URL, fileManager: FileManager) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxHashedBytes, let data = try? Data(contentsOf: url) else {
            return metadataStamp(url)
        }
        return InstructionFingerprint.of(String(decoding: data, as: UTF8.self))
    }

    private static func metadataStamp(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(size):\(modified)"
    }
}

public struct FolderWatch: Equatable, Sendable, Identifiable {
    public let relativePath: String
    public let project: Project
    public let resolvedPath: String
    public let snapshot: WatchSnapshot
    public let reportCount: Int
    public let instruction: String

    public var id: String { resolvedPath }

    public init(
        relativePath: String,
        project: Project,
        resolvedPath: String,
        snapshot: WatchSnapshot,
        reportCount: Int = 0,
        instruction: String = ""
    ) {
        self.relativePath = relativePath
        self.project = project
        self.resolvedPath = resolvedPath
        self.snapshot = snapshot
        self.reportCount = reportCount
        self.instruction = instruction
    }

    public var displayName: String {
        relativePath.isEmpty ? project.name : relativePath
    }

    public func matches(path: String) -> Bool {
        let wanted = WatchRequest(relativePath: path).displayPath
        return relativePath == wanted || displayName == path
    }

    public func advancing(to snapshot: WatchSnapshot, reported: Bool) -> FolderWatch {
        FolderWatch(
            relativePath: relativePath,
            project: project,
            resolvedPath: resolvedPath,
            snapshot: snapshot,
            reportCount: reportCount + (reported ? 1 : 0),
            instruction: instruction
        )
    }
}

public func watchFollowUpPrompt(
    watchName: String,
    changes: [WatchChange],
    instruction: String
) -> String? {
    let asked = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !asked.isEmpty, !asked.hasPrefix("/") else { return nil }
    guard !changes.isEmpty else { return nil }

    return """
    [Folder watch] \(WatchReport.headline(changes)) in \(watchName):
    \(WatchReport.describe(changes))

    This is the folder you were asked to keep an eye on. What you were asked was: \
    "\(asked)". If that says what to do when something turns up here — read it, \
    follow it, act on it — then do that now, for these files, and say what you did. \
    If it only asked to be told, answer in one short line. This is not a new \
    request and not a reason to start the earlier work again.
    """
}
