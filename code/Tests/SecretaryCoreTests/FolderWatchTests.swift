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

    func testHittingTheCapIsReported() throws {
        for index in 1...10 { try write("x", to: "file\(index).txt") }

        let snapshot = WatchScan.snapshot(of: root, limits: WatchLimits(maxEntries: 4))
        XCTAssertTrue(snapshot.wasTruncated)
        XCTAssertEqual(snapshot.count, 4)
    }

    func testAWatchedFileIsStampedByItsContents() throws {
        try write("hello", to: "notes.txt")
        let file = root.appendingPathComponent("notes.txt")

        let before = WatchScan.snapshot(of: file)
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

    func testOnlyReportedLooksAreCounted() {
        let quiet = watch("docs").advancing(to: WatchSnapshot(stamps: [:]), reported: false)
        XCTAssertEqual(quiet.reportCount, 0)
        XCTAssertEqual(quiet.advancing(to: WatchSnapshot(stamps: ["a": "1"]), reported: true).reportCount, 1)
    }

    func testAWatchIsIdentifiedByTheFolderItLandsOn() {
        let other = Project(name: "Other", path: "/tmp/other")
        XCTAssertEqual(watch("docs").id, watch("docs").id)
        XCTAssertNotEqual(watch("docs").id, watch("src").id)
        XCTAssertNotEqual(watch("docs").id, watch("docs", in: other).id)

        let once = watchOnlyProject(at: URL(fileURLWithPath: "/tmp/aaa"))
        let again = watchOnlyProject(at: URL(fileURLWithPath: "/tmp/aaa"))
        XCTAssertNotEqual(once.id, again.id, "a throwaway project is a new identity each time")
        XCTAssertEqual(watch("", in: once).id, watch("", in: again).id)
    }

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

    func testItCanOnlyRead() {
        let project = watchOnlyProject(at: url)
        XCTAssertEqual(project.allowedTools, [FileReadOnlyAdapter.toolIdentifier])
        XCTAssertEqual(project.allowedActions, ["read"])
    }
}

final class WatchRequestTests: XCTestCase {
    func testDotMeansTheProjectItself() {
        XCTAssertEqual(WatchRequest(relativePath: ".").displayPath, "")
        XCTAssertEqual(WatchRequest(relativePath: "./").displayPath, "")
        XCTAssertEqual(WatchRequest(relativePath: "docs").displayPath, "docs")
    }

    func testWatchingIsReadOnly() {
        XCTAssertEqual(WatchRequest(relativePath: "docs").actionClass, .readOnly)
    }
}

extension FolderWatchTests {

    func testTheFollowUpQuotesTheInstructionBackWithTheChange() {
        let prompt = watchFollowUpPrompt(
            watchName: "inbox",
            changes: [.added("order.csv")],
            instruction: "watch inbox and do whatever the file that lands there says"
        )
        guard let prompt else { return XCTFail("Expected a follow-up") }
        XCTAssertTrue(prompt.contains("order.csv"), "Got: \(prompt)")
        XCTAssertTrue(prompt.contains("inbox"), "Got: \(prompt)")
        XCTAssertTrue(
            prompt.contains("do whatever the file that lands there says"),
            "The instruction is several turns old — it has to be quoted. Got: \(prompt)"
        )
    }

    func testASlashCommandWatchAsksForNothing() {
        XCTAssertNil(
            watchFollowUpPrompt(
                watchName: "docs",
                changes: [.added("a.txt")],
                instruction: "/watch docs"
            )
        )
    }

    func testAWatchWithNoInstructionAsksForNothing() {
        XCTAssertNil(
            watchFollowUpPrompt(watchName: "docs", changes: [.added("a.txt")], instruction: "   ")
        )
    }

    func testNoChangesMeansNothingToSay() {
        XCTAssertNil(
            watchFollowUpPrompt(watchName: "docs", changes: [], instruction: "act on new files")
        )
    }

    func testTheFollowUpSaysItIsNotANewRequest() {
        let prompt = watchFollowUpPrompt(
            watchName: "inbox",
            changes: [.added("a.txt")],
            instruction: "act on new files"
        )
        XCTAssertTrue(prompt?.contains("not a new") ?? false, "Got: \(String(describing: prompt))")
    }

    func testAdvancingKeepsTheInstruction() {
        let watch = FolderWatch(
            relativePath: "inbox",
            project: Project(name: "P", path: "/tmp", allowedTools: [], allowedActions: []),
            resolvedPath: "/tmp/inbox",
            snapshot: WatchSnapshot(stamps: [:]),
            instruction: "act on new files"
        )
        XCTAssertEqual(
            watch.advancing(to: WatchSnapshot(stamps: ["a": "1"]), reported: true).instruction,
            "act on new files"
        )
    }
}
