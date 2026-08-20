import Foundation
import FunctionalCore

import Permissions
import ProjectRegistry
import ToolAdapters

/// A project that exists only to name one folder somebody approved watching.
///
/// Never registered and never saved. It is the smallest thing that carries
/// "this folder, read-only, right now" through code that expects a project —
/// and rooting it *at* that folder is what keeps the adapter's escape check
/// working every tick, now around the boundary that was just agreed to.
///
/// A new identity each time it is called, deliberately: a grant recorded
/// against it can never be matched again, so the same folder is asked about
/// afresh rather than quietly inheriting yesterday's yes.
public func watchOnlyProject(at url: URL) -> Project {
    Project(
        name: url.lastPathComponent,
        path: url.path,
        allowedTools: [FileReadOnlyAdapter.toolIdentifier],
        allowedActions: ["read"]
    )
}

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

    /// Where this points when it names somewhere outright rather than somewhere
    /// inside a project — an absolute path, or one starting at the home folder.
    ///
    /// Answered here, without a project, because it decides which way the
    /// request is routed *before* a project has been resolved: a full path is
    /// not a thing to look for inside a project and then refuse, it is a place
    /// the person named and can be asked about.
    ///
    /// Symlinks and `..` are resolved, so what the card shows is where the
    /// reading will actually happen. That is the whole point of showing it.
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
        // Two questions, each answered over one collection: what is in the new
        // snapshot that is new or different, and what was in the old one and
        // isn't there now. The accumulator this replaced could be read three
        // ways depending on where you entered the loop.
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
    /// The folder this actually landed on, symlinks resolved.
    ///
    /// Identity, and only identity. The loop deliberately re-resolves through
    /// the adapter on every tick instead of reusing this, so the escape check
    /// keeps running rather than being answered once at the start.
    public let resolvedPath: String
    public let snapshot: WatchSnapshot
    /// How many times something has been reported. Shown when it stops, so the
    /// person can tell "nothing happened" from "I wasn't looking".
    public let reportCount: Int
    /// What the person asked for when this watch started, verbatim.
    ///
    /// Held because the model is not: a change report was said into the
    /// transcript and never into the conversation, so the assistant never saw
    /// it happen and could not act on the standing instruction it had been
    /// given. Told "watch this folder and follow the instructions in whatever
    /// lands there", it reported the new file and did nothing with it — the
    /// owner's Sprint 21.2 report, and it reads as forgetting when it is really
    /// never having been told.
    ///
    /// Empty means nobody is asked to do anything: the watch reports, as it
    /// always did.
    public let instruction: String

    /// The folder itself, which is what "already watching that" is really
    /// asking about.
    ///
    /// It used to be the project's id plus the relative path. That answered the
    /// question only while every watch came through a registered project: a
    /// folder named outright is carried by a throwaway project made on the spot,
    /// so a second `/watch` of the same folder arrived with a different id and
    /// would have started a second watch reporting everything twice. The folder
    /// on disk can't drift like that.
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
            resolvedPath: resolvedPath,
            snapshot: snapshot,
            reportCount: reportCount + (reported ? 1 : 0),
            instruction: instruction
        )
    }
}

/// What the assistant is told when something changes under a watch it was asked
/// to act on.
///
/// The change goes to the *model*, not only into the transcript. `say` writes a
/// bubble and nothing else, so before this the assistant learned nothing at all
/// from a watch: the person saw "👁 1 change", the model saw nothing, and the
/// standing instruction — "when a file lands here, do what it says" — was never
/// reached. It looked like forgetting.
///
/// The instruction is quoted back rather than trusted to memory for the same
/// reason `OutstandingRequest.reminder` quotes the request back: it is several
/// turns old by now, and the app has it written down.
///
/// Returns nothing when nobody asked for anything to happen — a bare `/watch`
/// is a request to be told, and told is what `say` already did.
public func watchFollowUpPrompt(
    watchName: String,
    changes: [WatchChange],
    instruction: String
) -> String? {
    let asked = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    // A typed slash command says only "watch this", so there is nothing to
    // carry out and no turn worth spending on it.
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
