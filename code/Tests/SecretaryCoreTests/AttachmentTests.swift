import FunctionalCore
import XCTest
import AssistantState
import LLMProvider
import ProjectRegistry
@testable import SecretaryCore

final class AttachmentRuleTests: XCTestCase {

    func testTheKindComesFromTheName() {
        XCTAssertEqual(attachmentKind(for: "rows.CSV"), Option.some(.csv))
        XCTAssertEqual(attachmentKind(for: "notes.md"), Option.some(.markdown))
        XCTAssertEqual(attachmentKind(for: "config.json"), Option.some(.json))
        XCTAssertEqual(attachmentKind(for: ".env"), Option.some(.text), "A dotfile has no extension and is still text")
        XCTAssertEqual(attachmentKind(for: "Makefile"), Option.some(.text))
        XCTAssertEqual(attachmentKind(for: "form.png"), Option.some(.image))
    }

    func testSourceFilesSayTheyAreSource() {
        for name in ["App.swift", "main.py", "index.tsx", "build.gradle", "query.sql", "deploy.sh"] {
            XCTAssertEqual(attachmentKind(for: name), Option.some(.sourceCode), "Got: \(name)")
        }
    }

    func testAPdfIsItsOwnThingBecauseTheModelOpensIt() {
        XCTAssertEqual(attachmentKind(for: "invoice.PDF"), Option.some(.pdf))
    }

    func testOrdinaryNotesAndConfigurationAreText() {
        for name in ["notes.txt", "app.toml", "settings.ini", "data.xml", "changes.patch"] {
            XCTAssertEqual(attachmentKind(for: name), Option.some(.text), "Got: \(name)")
        }
    }

    func testTheNameWinsOverTheBytes() {
        XCTAssertEqual(
            admitting(name: "App.swift", bytes: 10, to: [], sniffed: .some(.text)),
            Either.right(.sourceCode)
        )
    }

    func testAnUnknownExtensionGetsInIfItsBytesAreText() {
        XCTAssertEqual(attachmentKind(for: "notes.zzz"), Option.none())
        XCTAssertEqual(
            admitting(name: "notes.zzz", bytes: 10, to: [], sniffed: textIfReadable(Data("hello".utf8))),
            Either.right(.text)
        )
    }

    func testSomethingThatIsNotTextAtAllIsRefused() {
        let binary = Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00, 0xFF, 0xFE])
        XCTAssertEqual(textIfReadable(binary), Option.none(), "A NUL byte is the giveaway")
        XCTAssertEqual(
            admitting(name: "book.xlsx", bytes: 10, to: [], sniffed: textIfReadable(binary)),
            Either.left(.unsupported(name: "book.xlsx"))
        )
    }

    func testAnEmptyReadDecidesNothing() {
        XCTAssertEqual(textIfReadable(Data()), Option.none())
    }

    func testTextIsNotOnlyEnglishText() {
        XCTAssertEqual(textIfReadable(Data("สวัสดีค่ะ".utf8)), Option.some(.text))
    }

    func testTheListStopsAtItsLimit() {
        let full = (1...attachmentLimit).map {
            Attachment(name: "f\($0).csv", stagedURL: URL(fileURLWithPath: "/x"), kind: .csv)
        }
        XCTAssertEqual(
            admitting(name: "one-more.csv", bytes: 10, to: full),
            Either.left(.tooMany(limit: attachmentLimit))
        )
    }

    func testSomethingTooBigToSendIsRefusedBeforeItIsCopied() {
        XCTAssertEqual(
            admitting(name: "video.png", bytes: attachmentMaxBytes + 1, to: []),
            Either.left(.tooLarge(name: "video.png", bytes: attachmentMaxBytes + 1))
        )
    }

    func testEveryRefusalHasWords() {
        let failures: [AttachmentError] = [
            .unsupported(name: "book.xlsx"),
            .tooLarge(name: "big.png", bytes: 9_000_000),
            .tooMany(limit: 5),
            .copyFailed(name: "rows.csv", message: "no such file")
        ]
        for failure in failures {
            XCTAssertTrue(failure.reason.count > 20, "Thin: \(failure.reason)")
        }
    }

    func testTheNoteNamesThePathsAndOnlyWhenThereAreSome() {
        XCTAssertEqual(attachmentNote([]), "")
        let note = attachmentNote([
            Attachment(name: "rows.csv", stagedURL: URL(fileURLWithPath: "/staged/rows.csv"), kind: .csv)
        ])
        XCTAssertTrue(note.contains("/staged/rows.csv"))
        XCTAssertTrue(note.contains("rows.csv (CSV)"))
    }

    func testTheAssistantCanAskForAFile() {
        let block = AttachBlock.parse("Send me the list.\n\n```attach\nthe spreadsheet with the rows\n```")
        XCTAssertEqual(block.asking, "the spreadsheet with the rows")
        XCTAssertEqual(block.body.trimmingCharacters(in: .whitespacesAndNewlines), "Send me the list.")
    }

    func testMentioningAFileIsNotAskingForOne() {
        XCTAssertEqual(AttachBlock.parse("You could upload the CSV if you like.").asking, nil)
    }

    func testAFileIsCopiedIntoTheAppsOwnFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("attach-\(UUID().uuidString)")
        let source = root.appendingPathComponent("from-desktop")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("rows.csv")
        try Data("name,email\na,b\n".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = FileAttachmentStore(directory: root.appendingPathComponent("staged"))
        let staged = try XCTUnwrap(store.stage(file, existing: []).fold({ _ in nil }, { $0 }))

        XCTAssertEqual(staged.name, "rows.csv")
        XCTAssertEqual(staged.kind, .csv)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.stagedURL.path))
        XCTAssertFalse(
            staged.stagedURL.path.contains("from-desktop"),
            "The model must be pointed at the copy, not the original: \(staged.stagedURL.path)"
        )
        XCTAssertEqual(try String(contentsOf: staged.stagedURL, encoding: .utf8), "name,email\na,b\n")

        store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.stagedURL.path))
    }

    func testAFileWithAnUnknownExtensionIsStagedWhenItIsText() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("attach-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let readable = root.appendingPathComponent("notes.zzz")
        try Data("just some notes\n".utf8).write(to: readable)
        let binary = root.appendingPathComponent("thing.zzz9")
        try Data([0x00, 0x01, 0x02, 0x00]).write(to: binary)

        let store = FileAttachmentStore(directory: root.appendingPathComponent("staged"))
        XCTAssertEqual(store.stage(readable, existing: []).fold({ _ in nil }, { $0.kind }), .text)
        XCTAssertTrue(store.stage(binary, existing: []).isLeft, "A file of NULs is not something to send")
    }

    func testTwoFilesWithOneNameDoNotOverwriteEachOther() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("attach-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a-rows.csv")
        let second = root.appendingPathComponent("b-rows.csv")
        try Data("1".utf8).write(to: first)
        try Data("2".utf8).write(to: second)

        let store = FileAttachmentStore(directory: root.appendingPathComponent("staged"))
        let one = try XCTUnwrap(store.stage(first, existing: []).fold({ _ in nil }, { $0 }))
        let two = try XCTUnwrap(store.stage(second, existing: [one]).fold({ _ in nil }, { $0 }))

        XCTAssertNotEqual(one.stagedURL, two.stagedURL)
        XCTAssertEqual(try String(contentsOf: one.stagedURL, encoding: .utf8), "1")
    }
}

@MainActor
final class AttachmentFlowTests: XCTestCase {
    private let machine = AssistantStateMachine()

    private func makeSecretary(
        _ provider: SpyWorkspaceProvider,
        store: AttachmentStaging
    ) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            activityPreference: InMemoryActivityPreference(),
            browserPreference: InMemoryBrowserPreference(),
            chatProvider: provider,
            attachmentStore: store
        )
    }

    private func settle() async {
        let deadline = Date().addingTimeInterval(2)
        while machine.state.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testAnAttachedFileWaitsAboveTheInputUntilTheMessageIsSent() async {
        let secretary = makeSecretary(SpyWorkspaceProvider(), store: InMemoryAttachmentStore())
        secretary.attach(URL(fileURLWithPath: "/tmp/rows.csv"))

        XCTAssertEqual(secretary.attachments.map(\.name), ["rows.csv"])

        secretary.submit("put these into the form")
        await settle()

        XCTAssertTrue(secretary.attachments.isEmpty, "They went with the message")
    }

    func testTheScreenShowsTheNameAndTheModelGetsThePath() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider, store: InMemoryAttachmentStore())
        secretary.attach(URL(fileURLWithPath: "/tmp/rows.csv"))

        secretary.submit("put these into the form")
        await settle()

        let onScreen = secretary.transcript.first { $0.speaker == .user }?.text ?? ""
        XCTAssertTrue(onScreen.contains("📎 rows.csv"))
        XCTAssertFalse(onScreen.contains("/staged/"), "The path is not for them: \(onScreen)")

        let sent = provider.lastMessages.last?.content ?? ""
        XCTAssertTrue(sent.contains("/staged/rows.csv"), "Got: \(sent)")
    }

    func testTheBackendIsOpenedOntoTheStagingFolderOnly() async {
        let provider = SpyWorkspaceProvider()
        let store = FileAttachmentStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("staged-\(UUID().uuidString)")
        )
        defer { store.clear() }
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("rows-\(UUID().uuidString).csv")
        try? Data("a,b\n".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let secretary = makeSecretary(provider, store: store)
        secretary.attach(source)
        secretary.submit("read this")
        await settle()

        let opened = provider.preparedExtras.last ?? []
        XCTAssertEqual(opened.map(\.lastPathComponent), [store.stagingDirectory.toOptional()!.lastPathComponent])
    }

    func testAFileOnItsOwnIsAMessage() async {
        let provider = SpyWorkspaceProvider()
        let secretary = makeSecretary(provider, store: InMemoryAttachmentStore())
        secretary.attach(URL(fileURLWithPath: "/tmp/rows.csv"))

        secretary.submit("")
        await settle()

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertTrue((provider.lastMessages.last?.content ?? "").contains("rows.csv"))
    }

    func testARefusedFileIsSaidOutLoudAndAttachesNothing() {
        let store = InMemoryAttachmentStore()
        let secretary = makeSecretary(SpyWorkspaceProvider(), store: store)

        secretary.attach(URL(fileURLWithPath: "/tmp/book.xlsx"))

        XCTAssertTrue(secretary.attachments.isEmpty)
        XCTAssertTrue(
            secretary.transcript.contains { $0.text.contains("book.xlsx") },
            "A file that lands nowhere and says nothing is one they believe they sent"
        )
    }

    func testTakingOneBackOffTheList() {
        let secretary = makeSecretary(SpyWorkspaceProvider(), store: InMemoryAttachmentStore())
        secretary.attach(URL(fileURLWithPath: "/tmp/a.csv"))
        secretary.attach(URL(fileURLWithPath: "/tmp/b.csv"))

        secretary.detach(secretary.attachments[0].id)

        XCTAssertEqual(secretary.attachments.map(\.name), ["b.csv"])
    }

    func testANewConversationThrowsTheCopiesAway() {
        let store = InMemoryAttachmentStore()
        let secretary = makeSecretary(SpyWorkspaceProvider(), store: store)
        secretary.attach(URL(fileURLWithPath: "/tmp/a.csv"))

        secretary.newConversation()

        XCTAssertTrue(secretary.attachments.isEmpty)
        XCTAssertEqual(store.cleared, 1)
    }

    func testAskingForAFilePutsAButtonUpAndNotRawText() async {
        let provider = SpyWorkspaceProvider()
        provider.replyForNextTurn = "I'll need the list.\n\n```attach\nthe spreadsheet with the rows\n```"
        let secretary = makeSecretary(provider, store: InMemoryAttachmentStore())

        secretary.submit("enter my expenses")
        await settle()

        XCTAssertEqual(secretary.fileRequest, Option.some("the spreadsheet with the rows"))
        XCTAssertFalse(
            secretary.transcript.contains { $0.text.contains("```attach") },
            "The marker is for the app, not for the person"
        )
    }

    func testChoosingAFileTakesTheButtonAway() async {
        let provider = SpyWorkspaceProvider()
        provider.replyForNextTurn = "```attach\nthe rows\n```"
        let secretary = makeSecretary(provider, store: InMemoryAttachmentStore())
        secretary.submit("enter my expenses")
        await settle()

        secretary.attach(URL(fileURLWithPath: "/tmp/rows.csv"))

        XCTAssertEqual(secretary.fileRequest, Option.none())
    }

    func testMovingOnTakesTheButtonAwayToo() async {
        let provider = SpyWorkspaceProvider()
        provider.replyForNextTurn = "```attach\nthe rows\n```"
        let secretary = makeSecretary(provider, store: InMemoryAttachmentStore())
        secretary.submit("enter my expenses")
        await settle()

        secretary.submit("actually, never mind")
        await settle()

        XCTAssertEqual(secretary.fileRequest, Option.none())
    }

    func testTheDropAreaInvitesAFileWhenNothingIsAttached() {
        XCTAssertEqual(
            attachmentDropPrompt(attached: 0),
            "Drop a file — anywhere in this window"
        )
    }

    func testTheDropAreaSaysHowMuchRoomIsLeft() {
        XCTAssertEqual(attachmentDropPrompt(attached: 1), "Drop to add — room for 4 more")
        XCTAssertEqual(attachmentDropPrompt(attached: 4), "Drop to add — room for 1 more")
    }

    func testTheDropAreaRefusesBeforeTheDropWhenTheListIsFull() {
        let full = attachmentDropPrompt(attached: attachmentLimit)
        XCTAssertEqual(full, "Already holding 5 — send these before adding more")
        XCTAssertEqual(attachmentDropPrompt(attached: attachmentLimit + 1), full,
                       "over the limit reads the same as at it")
    }

    func testTheDropAreaAndTheAdmissionRuleAgree() {
        for attached in 0...(attachmentLimit + 1) {
            let existing = [Attachment](repeating: sampleAttachment, count: attached)
            let admits = admitting(name: "notes.md", bytes: 10, to: existing).isRight
            let invites = !attachmentDropPrompt(attached: attached).hasPrefix("Already holding")
            XCTAssertEqual(invites, admits, "disagreed at \(attached) attached")
        }
    }

    private var sampleAttachment: Attachment {
        Attachment(
            name: "notes.md",
            stagedURL: URL(fileURLWithPath: "/tmp/notes.md"),
            kind: .markdown
        )
    }
}
