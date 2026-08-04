import XCTest
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
    func testTheProjectFolderIsNamedAfterTheProject() {
        let watch = FolderWatch(relativePath: "", snapshot: WatchSnapshot(stamps: [:]))
        XCTAssertEqual(watch.displayName(inProject: "AI-Secretary"), "AI-Secretary")
    }

    func testASubfolderIsNamedByItsPath() {
        let watch = FolderWatch(relativePath: "docs", snapshot: WatchSnapshot(stamps: [:]))
        XCTAssertEqual(watch.displayName(inProject: "AI-Secretary"), "docs")
    }

    /// Counting only what was actually said tells "nothing happened" apart from
    /// "I wasn't looking" when the watch is stopped.
    func testOnlyReportedLooksAreCounted() {
        let watch = FolderWatch(relativePath: "docs", snapshot: WatchSnapshot(stamps: [:]))
        let quiet = watch.advancing(to: WatchSnapshot(stamps: [:]), reported: false)
        XCTAssertEqual(quiet.reportCount, 0)
        XCTAssertEqual(quiet.advancing(to: WatchSnapshot(stamps: ["a": "1"]), reported: true).reportCount, 1)
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
