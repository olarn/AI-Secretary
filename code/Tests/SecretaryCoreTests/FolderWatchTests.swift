import XCTest
import ProjectRegistry
import ToolAdapters
@testable import SecretaryCore

final class WatchSnapshotTests: XCTestCase {
    private func snapshot(_ pairs: [String: String]) -> WatchSnapshot {
        WatchSnapshot(stamps: pairs)
    }

    func testNothingChangedIsNoChanges() {
        let before = snapshot(["a.txt": "1", "b.txt": "2"])
        XCTAssertTrue(before.changes(to: before).isEmpty)
    }

    func testItSeesAdditionsRemovalsAndEdits() {
        let before = snapshot(["kept.txt": "1", "edited.txt": "1", "gone.txt": "1"])
        let after = snapshot(["kept.txt": "1", "edited.txt": "2", "new.txt": "1"])
        XCTAssertEqual(
            before.changes(to: after),
            [.modified("edited.txt"), .removed("gone.txt"), .added("new.txt")]
        )
    }

    /// Sorted, so the same change reads the same way twice and a report isn't
    /// reshuffled by dictionary order between two looks at the same folder.
    func testTheOrderIsStable() {
        let before = snapshot([:])
        let after = snapshot(["c": "1", "a": "1", "b": "1"])
        XCTAssertEqual(before.changes(to: after).map(\.path), ["a", "b", "c"])
    }
}

final class WatchReportTests: XCTestCase {
    func testItNamesWhatHappenedToEachFile() {
        let text = WatchReport.describe([.added("new.txt"), .removed("old.txt"), .modified("x.txt")])
        XCTAssertEqual(text, "+ new.txt\n− old.txt\n~ x.txt")
    }

    /// A `git checkout` under a watched folder is hundreds of changes at once.
    /// The list is capped so the message stays readable — but the count is not,
    /// because a summary that understates what happened is worse than a long one.
    func testALongListIsCappedButTheCountIsExact() {
        let changes = (1...20).map { WatchChange.modified("file\($0).txt") }
        let text = WatchReport.describe(changes)
        XCTAssertTrue(text.contains("…and 14 more"), "Got: \(text)")
        XCTAssertEqual(WatchReport.headline(changes), "20 changes")
    }

    func testOneChangeIsSingular() {
        XCTAssertEqual(WatchReport.headline([.added("a")]), "1 change")
    }
}

final class WatchScanTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testItSeesTheFilesInAFolder() throws {
        try write("one", to: "a.txt")
        try write("two", to: "nested/b.txt")

        let snapshot = WatchScan.snapshot(of: root)
        XCTAssertEqual(Set(snapshot.stamps.keys), ["a.txt", "nested/b.txt"])
        XCTAssertFalse(snapshot.wasTruncated)
    }

    /// Build output and dependency trees churn constantly and mean nothing to
    /// the person watching. Descending into them would also be the difference
    /// between watching a project and re-reading a repository every 4 seconds.
    func testItNeverDescendsIntoBuildOutput() throws {
        try write("real", to: "src.swift")
        try write("noise", to: ".build/debug/thing.o")
        try write("noise", to: "node_modules/pkg/index.js")

        XCTAssertEqual(Set(WatchScan.snapshot(of: root).stamps.keys), ["src.swift"])
    }

    func testItStopsAtTheDepthLimit() throws {
        try write("deep", to: "a/b/c/d/e/deep.txt")
        try write("shallow", to: "top.txt")

        let snapshot = WatchScan.snapshot(of: root, limits: WatchLimits(maxDepth: 2))
        XCTAssertEqual(Set(snapshot.stamps.keys), ["top.txt"])
    }

    /// Hitting the cap has to be visible. "Watching this folder" and "watching
    /// the first N files of it" are different promises, and the second one
    /// silently pretending to be the first is the failure worth guarding.
    func testHittingTheCapIsReported() throws {
        for index in 1...10 { try write("x", to: "file\(index).txt") }

        let snapshot = WatchScan.snapshot(of: root, limits: WatchLimits(maxEntries: 4))
        XCTAssertTrue(snapshot.wasTruncated)
        XCTAssertEqual(snapshot.count, 4)
    }

    /// A single watched file is watched for its *contents*: saving it again
    /// unchanged moves its modification date, and reporting that as a change
    /// would make the feature cry wolf on every ⌘S.
    func testAWatchedFileIsStampedByItsContents() throws {
        try write("hello", to: "notes.txt")
        let file = root.appendingPathComponent("notes.txt")

        let before = WatchScan.snapshot(of: file)
        // Rewrite the same text — new mtime, same contents.
        try write("hello", to: "notes.txt")
        XCTAssertTrue(before.changes(to: WatchScan.snapshot(of: file)).isEmpty)

        try write("goodbye", to: "notes.txt")
        XCTAssertEqual(
            before.changes(to: WatchScan.snapshot(of: file)),
            [.modified("notes.txt")]
        )
    }

    func testAMissingPathIsAnEmptySnapshotRatherThanACrash() {
        let missing = root.appendingPathComponent("nope")
        XCTAssertEqual(WatchScan.snapshot(of: missing).count, 0)
    }
}

final class FolderWatchTests: XCTestCase {
    private let project = Project(name: "AI-Secretary", path: "/tmp/ai-secretary")

    private func watch(_ path: String, in project: Project? = nil) -> FolderWatch {
        let owner = project ?? self.project
        return FolderWatch(
            relativePath: path,
            project: owner,
            resolvedPath: path.isEmpty ? owner.path : "\(owner.path)/\(path)",
            snapshot: WatchSnapshot(stamps: [:])
        )
    }

    func testTheProjectFolderIsNamedAfterTheProject() {
        XCTAssertEqual(watch("").displayName, "AI-Secretary")
    }

    func testASubfolderIsNamedByItsPath() {
        XCTAssertEqual(watch("docs").displayName, "docs")
    }

    /// Counting only what was actually said tells "nothing happened" apart from
    /// "I wasn't looking" when the watch is stopped.
    func testOnlyReportedLooksAreCounted() {
        let quiet = watch("docs").advancing(to: WatchSnapshot(stamps: [:]), reported: false)
        XCTAssertEqual(quiet.reportCount, 0)
        XCTAssertEqual(quiet.advancing(to: WatchSnapshot(stamps: ["a": "1"]), reported: true).reportCount, 1)
    }

    /// Identity is the folder on disk. Two projects each with a `docs` are two
    /// folders and so two watches; the same folder reached twice is one, however
    /// it was named — which is what stops a folder named by full path, carried
    /// by a throwaway project with a fresh id, from being watched twice over.
    func testAWatchIsIdentifiedByTheFolderItLandsOn() {
        let other = Project(name: "Other", path: "/tmp/other")
        XCTAssertEqual(watch("docs").id, watch("docs").id)
        XCTAssertNotEqual(watch("docs").id, watch("src").id)
        XCTAssertNotEqual(watch("docs").id, watch("docs", in: other).id)

        // Same folder, two throwaway projects — one watch, not two.
        let once = watchOnlyProject(at: URL(fileURLWithPath: "/tmp/aaa"))
        let again = watchOnlyProject(at: URL(fileURLWithPath: "/tmp/aaa"))
        XCTAssertNotEqual(once.id, again.id, "a throwaway project is a new identity each time")
        XCTAssertEqual(watch("", in: once).id, watch("", in: again).id)
    }

    /// `/watch stop <path>` has to answer to what the person sees in the
    /// messages, which for the project folder is the project's name.
    func testStoppingByNameMatchesWhatTheMessagesShow() {
        XCTAssertTrue(watch("docs").matches(path: "docs"))
        XCTAssertTrue(watch("").matches(path: "."), "`.` is how the project folder was started")
        XCTAssertTrue(watch("").matches(path: "AI-Secretary"), "and how it is named back")
        XCTAssertFalse(watch("docs").matches(path: "src"))
    }
}

final class WatchAbsoluteTargetTests: XCTestCase {
    private func target(_ path: String) -> String? {
        WatchRequest(relativePath: path).absoluteTarget.toOptional()?.path
    }

    /// A path inside a project is not this: it has to go through the project so
    /// the escape check applies to it.
    func testARelativePathIsNotAnOutrightPlace() {
        XCTAssertNil(target("docs"))
        XCTAssertNil(target("."))
        XCTAssertNil(target("../sibling"), "climbing out is caught later, against the real project root")
    }

    func testAFullPathNamesItsPlace() {
        XCTAssertEqual(target("/tmp"), URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().path)
    }

    func testHomeIsSpelledOutRatherThanLeftAsATilde() {
        XCTAssertEqual(target("~"), NSHomeDirectory())
        XCTAssertEqual(target(" ~/Desktop "), "\(NSHomeDirectory())/Desktop")
    }

    /// The card shows this string, so it has to be where the reading will
    /// actually happen — on macOS `/tmp` is a link to `/private/tmp`, and a card
    /// that says the former while reading the latter is the failure mode.
    func testSymlinksAreResolvedBeforeAnyoneIsAsked() {
        XCTAssertEqual(target("/tmp/../tmp"), URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().path)
    }
}

final class FolderProjectTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/watch-me")

    func testItIsRootedAtTheApprovedFolder() {
        let project = watchOnlyProject(at: url)
        XCTAssertEqual(project.path, url.path)
        XCTAssertEqual(project.name, "watch-me", "the card and the badge call it by its own name")
    }

    /// Read-only and nothing else. It exists to carry one yes about one folder,
    /// not to become a project by the back door.
    func testItCanOnlyRead() {
        let project = watchOnlyProject(at: url)
        XCTAssertEqual(project.allowedTools, [FileReadOnlyAdapter.toolIdentifier])
        XCTAssertEqual(project.allowedActions, ["read"])
    }
}

final class WatchRequestTests: XCTestCase {
    /// "." is how people say "this folder", and it reads as a filename
    /// everywhere else, so it's normalised once at the edge.
    func testDotMeansTheProjectItself() {
        XCTAssertEqual(WatchRequest(relativePath: ".").displayPath, "")
        XCTAssertEqual(WatchRequest(relativePath: "./").displayPath, "")
        XCTAssertEqual(WatchRequest(relativePath: "docs").displayPath, "docs")
    }

    /// Weaker than reading a file *to the model*: nothing leaves the machine.
    func testWatchingIsReadOnly() {
        XCTAssertEqual(WatchRequest(relativePath: "docs").actionClass, .readOnly)
    }
}
