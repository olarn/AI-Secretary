import FunctionalCore
import XCTest
@testable import SecretaryCore

final class ConversationArchiveTests: XCTestCase {

    private func user(_ text: String) -> TranscriptEntry {
        TranscriptEntry(speaker: .user, text: text)
    }

    private func said(_ text: String) -> TranscriptEntry {
        TranscriptEntry(speaker: .secretary, text: text, speakerName: "Miku")
    }

    func testAConversationNobodySpokeInIsNotArchived() {
        XCTAssertFalse(worthArchiving([]))
        XCTAssertFalse(worthArchiving([said("Hello!")]))
        XCTAssertFalse(worthArchiving([
            TranscriptEntry(speaker: .secretary, kind: .activity, text: "Reading a file")
        ]))
        XCTAssertTrue(worthArchiving([user("hello"), said("hi")]))
    }

    func testOnlyAUserMessageCounts() {
        XCTAssertFalse(worthArchiving([TranscriptEntry(speaker: .user, kind: .activity, text: "x")]))
    }

    func testATranscriptOfNothingButCommandsIsNotAConversation() {
        XCTAssertFalse(worthArchiving([user("/history 1"), said("Picked up …")]))
        XCTAssertFalse(worthArchiving([user("/new")]))
        XCTAssertTrue(worthArchiving([user("/model sonnet"), user("now a real question")]))
    }

    func testTheTitleIsNeverACommand() {
        XCTAssertEqual(
            conversationTitle(from: [user("/model sonnet"), said("ok"), user("what changed?")]),
            "what changed?"
        )
    }

    func testTheClosingCommandIsNotFiledWithTheConversation() {
        let entries = archivableEntries([user("a real question"), said("an answer"), user("/new")])
        XCTAssertEqual(entries.map(\.text), ["a real question", "an answer"])
    }

    func testACommandInTheMiddleIsKept() {
        let entries = archivableEntries([user("question"), user("/model sonnet"), said("answer")])
        XCTAssertEqual(entries.count, 3)
    }

    func testTheTitleIsTheOpeningQuestion() {
        XCTAssertEqual(conversationTitle(from: [user("summarise my notes"), said("sure")]),
                       "summarise my notes")
    }

    func testTheTitleSkipsWhatTheSecretarySaidFirst() {
        XCTAssertEqual(conversationTitle(from: [said("Hello!"), user("fix the build")]), "fix the build")
    }

    func testALongTitleIsCutOnAWordBoundary() {
        let title = conversationTitle(
            from: [user("please go through every file in the vault and tell me what changed")],
            limit: 20
        )
        XCTAssertTrue(title.hasSuffix("…"), "Got: \(title)")
        XCTAssertFalse(title.contains("  "))
        XCTAssertTrue("please go through every file in the vault and tell me what changed"
            .hasPrefix(title.dropLast()), "Got: \(title)")
        XCTAssertFalse(title.dropLast().hasSuffix(" "), "No trailing space before the ellipsis: \(title)")
    }

    func testOneVeryLongWordIsCutHardRatherThanLeavingAStub() {
        let title = conversationTitle(from: [user("a supercalifragilisticexpialidocious")], limit: 20)
        XCTAssertEqual(title.count, 21, "20 characters plus the ellipsis: \(title)")
    }

    func testTheTitleIsASingleLine() {
        let title = conversationTitle(from: [user("first line\nsecond line\n\nthird")])
        XCTAssertFalse(title.contains("\n"), "Got: \(title)")
        XCTAssertEqual(title, "first line second line third")
    }

    func testAConversationWithNoWordsStillHasAName() {
        XCTAssertEqual(conversationTitle(from: []), "Untitled conversation")
        XCTAssertEqual(conversationTitle(from: [user("   ")]), "Untitled conversation")
    }

    private func stub(_ name: String, id: UUID = UUID()) -> ArchivedConversation {
        ArchivedConversation(id: id, title: name, entries: [])
    }

    func testTheNewestIsFirst() {
        let history = archiving(stub("second"), into: [stub("first")])
        XCTAssertEqual(history.map(\.title), ["second", "first"])
    }

    func testTheOldestFallsOffTheEnd() {
        var history: [ArchivedConversation] = []
        for i in 1...12 { history = archiving(stub("chat \(i)"), into: history) }

        XCTAssertEqual(history.count, conversationHistoryLimit)
        XCTAssertEqual(history.first?.title, "chat 12")
        XCTAssertEqual(history.last?.title, "chat 3", "chats 1 and 2 should have fallen off")
    }

    func testReArchivingReplacesInPlaceRatherThanDuplicating() {
        let id = UUID()
        let history = archiving(stub("same chat", id: id), into: [stub("same chat", id: id), stub("other")])

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.map(\.title), ["same chat", "other"])
    }

    func testTheLabelSaysHowLongAgo() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func label(daysAgo: Int) -> String {
            conversationMenuLabel(
                title: "notes",
                savedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!,
                now: now
            )
        }
        XCTAssertTrue(label(daysAgo: 0).hasSuffix("today"), label(daysAgo: 0))
        XCTAssertTrue(label(daysAgo: 1).hasSuffix("yesterday"), label(daysAgo: 1))
        XCTAssertTrue(label(daysAgo: 3).hasSuffix("3 days ago"), label(daysAgo: 3))
        XCTAssertFalse(label(daysAgo: 40).contains("ago"), "Past a week it should be a date: \(label(daysAgo: 40))")
        XCTAssertTrue(label(daysAgo: 0).hasPrefix("notes"))
    }

    func testTheRowKnowsWhichConversationIsOpen() {
        let mine = UUID()
        let rows = conversationMenuRows(
            [stub("open one", id: mine), stub("other")],
            current: .some(mine)
        )
        XCTAssertEqual(rows.map(\.isCurrent), [true, false])
        XCTAssertEqual(rows.map(\.id).first, mine)
    }

    func testNothingIsMarkedCurrentWhenTheLiveChatIsNew() {
        let rows = conversationMenuRows([stub("a"), stub("b")], current: .none())
        XCTAssertEqual(rows.filter(\.isCurrent).count, 0)
    }

    func testAConversationSurvivesARoundTripThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileConversationStore(fileURL: url)
        let project = UUID()
        let original = ArchivedConversation(
            title: "the vault",
            sessionID: .some("abc-123"),
            projectID: .some(project),
            entries: [
                user("what changed?"),
                said("Two files."),
                TranscriptEntry(speaker: .secretary, kind: .activity, text: "Reading"),
                TranscriptEntry(speaker: .secretary, kind: .failure, text: "Couldn't reach Claude Code"),
                TranscriptEntry(speaker: .secretary, kind: .divider, text: "New conversation.")
            ]
        )

        XCTAssertTrue(store.save([original]).isRight)
        let loaded = try XCTUnwrap(store.load().fold({ _ in nil }, { $0.first }))

        XCTAssertEqual(loaded.id, original.id)
        XCTAssertEqual(loaded.title, "the vault")
        XCTAssertEqual(loaded.sessionID, Option.some("abc-123"))
        XCTAssertEqual(loaded.projectID, Option.some(project))
        XCTAssertEqual(loaded.entries.map(\.text), original.entries.map(\.text))
        XCTAssertEqual(loaded.entries.map(\.kind), original.entries.map(\.kind))
        XCTAssertEqual(loaded.entries.map(\.speaker), original.entries.map(\.speaker))
        XCTAssertEqual(loaded.entries.map(\.speakerName), original.entries.map(\.speakerName))
    }

    func testAConversationWithNoSessionStaysThatWay() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileConversationStore(fileURL: url)
        _ = store.save([ArchivedConversation(title: "never sent", entries: [user("hi")])])

        let loaded = try XCTUnwrap(store.load().fold({ _ in nil }, { $0.first }))
        XCTAssertEqual(loaded.sessionID, Option.none())
        XCTAssertEqual(loaded.projectID, Option.none())
    }

    func testNoFileYetIsAnEmptyHistoryRatherThanAFailure() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).json")
        XCTAssertEqual(FileConversationStore(fileURL: url).load().fold({ _ in nil }, { $0.count }), 0)
    }

    func testAnUnreadableFileFailsAsAValue() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)

        XCTAssertTrue(FileConversationStore(fileURL: url).load().isLeft)
    }
}
