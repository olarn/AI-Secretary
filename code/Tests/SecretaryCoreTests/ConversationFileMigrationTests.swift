import XCTest
@testable import SecretaryCore

final class ConversationFileMigrationTests: XCTestCase {
    private let legacy = URL(fileURLWithPath: "/tmp/AISecretary/conversations.json")
    private let mine = URL(fileURLWithPath: "/tmp/AISecretary/conversations-ABC.json")

    func testTheOldFileBecomesHersWhenSheHasNoneOfHerOwn() {
        XCTAssertEqual(
            conversationFileMigration(
                legacy: legacy,
                perCharacter: mine,
                legacyExists: true,
                perCharacterExists: false
            ),
            .adopt(from: legacy, to: mine)
        )
    }

    func testAdoptionNeverOverwritesAHistorySheAlreadyHas() {
        XCTAssertEqual(
            conversationFileMigration(
                legacy: legacy,
                perCharacter: mine,
                legacyExists: true,
                perCharacterExists: true
            ),
            .none
        )
    }

    func testAFreshInstallHasNothingToAdopt() {
        XCTAssertEqual(
            conversationFileMigration(
                legacy: legacy,
                perCharacter: mine,
                legacyExists: false,
                perCharacterExists: false
            ),
            .none
        )
    }

    func testACharacterWithHerOwnFileAndNoOldFileIsLeftAlone() {
        XCTAssertEqual(
            conversationFileMigration(
                legacy: legacy,
                perCharacter: mine,
                legacyExists: false,
                perCharacterExists: true
            ),
            .none
        )
    }

    func testEachCharacterGetsHerOwnPath() {
        let one = UUID()
        let two = UUID()

        XCTAssertNotEqual(
            FileConversationStore.url(forCharacter: one),
            FileConversationStore.url(forCharacter: two)
        )
        XCTAssertNotEqual(FileConversationStore.url(forCharacter: one), FileConversationStore.defaultURL)
    }

    func testTheFileIsActuallyMovedOnDisk() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let from = directory.appendingPathComponent("conversations.json")
        let to = directory.appendingPathComponent("conversations-ABC.json")
        try Data("[]".utf8).write(to: from)

        XCTAssertEqual(
            conversationFileMigration(
                legacy: from,
                perCharacter: to,
                legacyExists: FileManager.default.fileExists(atPath: from.path),
                perCharacterExists: FileManager.default.fileExists(atPath: to.path)
            ),
            .adopt(from: from, to: to)
        )

        try FileManager.default.moveItem(at: from, to: to)

        XCTAssertFalse(FileManager.default.fileExists(atPath: from.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: to.path))
    }
}
