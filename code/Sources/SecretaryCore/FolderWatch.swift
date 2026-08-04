import Foundation

import Permissions
import ProjectRegistry

/// A path the person asked to be told about.
///
/// `.readOnly`: nothing is written and nothing leaves the machine — it is
/// repeated reading of files in a project they already approved. That is a
/// weaker grant than `InstructionRequest`, deliberately, and the difference is
/// exactly whether the bytes go anywhere.
public struct WatchRequest: Equatable, Sendable {
    public let relativePath: String

    public init(relativePath: String) {
        self.relativePath = relativePath
    }

    /// `.` is the natural way to say "this project", and reads badly
    /// everywhere else, so it is normalised once here.
    public var displayPath: String {
        let trimmed = relativePath.trimmingCharacters(in: .whitespaces)
        return (trimmed == "." || trimmed == "./") ? "" : trimmed
    }

    public var actionClass: ActionClass { .readOnly }

    public var humanDescription: String {
        "Keep an eye on \(displayPath.isEmpty ? "this project folder" : displayPath) and say when it changes"
    }
}

/// What changed under a watched path between two looks.
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

/// The most that can be watched at once.
///
/// Each one costs a walk of up to `WatchLimits.maxEntries` every few seconds,
/// so this is the same argument as those caps, one level up: several watches
/// are genuinely useful — a folder for new files and a document for edits —
/// but an unbounded list is an unbounded amount of work on a timer. Hitting it
/// refuses the new one and leaves everything already running alone.
public let maxConcurrentWatches = 5

/// How much of a folder is worth looking at.
///
/// The caps are not tuning knobs, they are the feature working at all: a
/// registered project is often a whole repository, and `.build` alone can hold
/// tens of thousands of files. Re-stamping those every few seconds would be a
/// background process quietly eating the user's Mac, which is the opposite of
/// what a desktop companion is allowed to be.
public struct WatchLimits: Equatable, Sendable {
    public let maxEntries: Int
    public let maxDepth: Int
    /// Directories never descended into: build output and dependency trees
    /// change constantly and mean nothing to the person watching.
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

/// One look at a path: every entry that was there, and a stamp saying what it
/// was like.
///
/// The stamp is size-and-modification-time for entries under a folder, and the
/// content digest for a single watched file. That split is the two backlog
/// bullets: a folder is being watched for *what appeared, vanished or moved*,
/// where cheap identity is enough and hashing every file would be absurd; a
/// single file is being watched for *whether its contents changed*, which is
/// the only question a stamp can't answer honestly — saving a file unchanged
/// moves its mtime.
public struct WatchSnapshot: Equatable, Sendable {
    public let stamps: [String: String]
    /// True when the walk hit `maxEntries` and stopped. Surfaced to the user,
    /// never swallowed: "watching this folder" and "watching the first 500
    /// files of this folder" are different promises.
    public let wasTruncated: Bool

    public init(stamps: [String: String], wasTruncated: Bool = false) {
        self.stamps = stamps
        self.wasTruncated = wasTruncated
    }

    public var count: Int { stamps.count }

    /// Sorted so the same change set always reads the same way, and so a test
    /// doesn't depend on dictionary order.
    public func changes(to later: WatchSnapshot) -> [WatchChange] {
        var changes: [WatchChange] = []
        for (path, stamp) in later.stamps {
            guard let before = stamps[path] else {
                changes.append(.added(path))
                continue
            }
            if before != stamp { changes.append(.modified(path)) }
        }
        for path in stamps.keys where later.stamps[path] == nil {
            changes.append(.removed(path))
        }
        return changes.sorted { $0.path < $1.path }
    }
}

/// How a set of changes is announced.
///
/// Capped, because a `git checkout` under a watched folder produces hundreds of
/// changes at once and a message listing them all is a message nobody reads —
/// but the count is always exact, so the summary never understates what
/// happened.
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

    /// "3 changes" / "1 change" — the headline, always the true total.
    public static func headline(_ changes: [WatchChange]) -> String {
        changes.count == 1 ? "1 change" : "\(changes.count) changes"
    }
}

/// Takes a look at a path on disk.
///
/// Lives here rather than in an adapter because what it produces is a value the
/// rest of the app compares and renders; the only thing it borrows from
/// Foundation is the directory listing. The caller has already resolved the URL
/// through the project's own rules — nothing here joins a path from user text.
public enum WatchScan {
    /// The most a single file's contents are read before falling back to its
    /// size and date. A watched log can grow without bound and must not be
    /// pulled into memory every few seconds.
    static let maxHashedBytes = 1_000_000

    public static func snapshot(
        of target: URL,
        limits: WatchLimits = WatchLimits(),
        fileManager: FileManager = .default
    ) -> WatchSnapshot {
        // Resolved once, up front, and used for both the walk and the relative
        // paths. `contentsOfDirectory` hands back real paths, so on a Mac where
        // the folder is under /var the listing comes out as /private/var and
        // stripping the unresolved root leaves mangled names like
        // "/privatesrc.swift" — every entry then reads as added-and-removed on
        // the next look.
        let url = target.resolvingSymlinksInPath().standardizedFileURL

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

    /// Contents, so that saving a file without changing it isn't reported as a
    /// change — the whole point of watching one file rather than its folder.
    private static func fileStamp(_ url: URL, fileManager: FileManager) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxHashedBytes, let data = try? Data(contentsOf: url) else {
            return metadataStamp(url)
        }
        return InstructionFingerprint.of(String(decoding: data, as: UTF8.self))
    }

    /// Size and modification date. Cheap enough to do to hundreds of entries on
    /// a timer, which contents are not.
    private static func metadataStamp(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(size):\(modified)"
    }
}

/// A path being watched, and what it looked like last time.
///
/// Carries its own project rather than borrowing one from beside it: several
/// of these run at once and they need not be in the same project, so a single
/// "the project being watched" would be a value that is right for one of them
/// and wrong for the rest.
public struct FolderWatch: Equatable, Sendable, Identifiable {
    /// Relative to the project. Empty means the project folder itself.
    public let relativePath: String
    public let project: Project
    public let snapshot: WatchSnapshot
    /// How many times something has been reported. Shown when it stops, so the
    /// person can tell "nothing happened" from "I wasn't looking".
    public let reportCount: Int

    /// A path inside a project. Two watches on the same path in the same
    /// project are the same watch, which is what makes "already watching that"
    /// answerable.
    public var id: String { "\(project.id)/\(relativePath)" }

    public init(relativePath: String, project: Project, snapshot: WatchSnapshot, reportCount: Int = 0) {
        self.relativePath = relativePath
        self.project = project
        self.snapshot = snapshot
        self.reportCount = reportCount
    }

    /// The name to use in a message. The project's own folder has no relative
    /// path, and "watching “”" reads as a bug.
    public var displayName: String {
        relativePath.isEmpty ? project.name : relativePath
    }

    /// Whether the person meant this one when they typed a path. They type
    /// what they see in the messages, so both spellings have to answer.
    public func matches(path: String) -> Bool {
        let wanted = WatchRequest(relativePath: path).displayPath
        return relativePath == wanted || displayName == path
    }

    public func advancing(to snapshot: WatchSnapshot, reported: Bool) -> FolderWatch {
        FolderWatch(
            relativePath: relativePath,
            project: project,
            snapshot: snapshot,
            reportCount: reportCount + (reported ? 1 : 0)
        )
    }
}
