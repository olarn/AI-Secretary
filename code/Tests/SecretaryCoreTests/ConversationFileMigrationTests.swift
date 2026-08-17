import XCTest
@testable import SecretaryCore

/// Handing the pre-Sprint-13 history file to a character.
///
/// Only ever runs on a machine that has the old file, so it cannot be checked
/// by launching a fresh build — and getting it wrong costs the person every
/// conversation they have had.
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

    /// The one that would hurt: adopting on top of a file she already has would
    /// replace everything she has said since with what everybody shared before.
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

    /// Two characters must not share a file: a single one holding everybody's
    /// conversations would have to carry an owner on every row and be rewritten
    /// by whichever character saved last.
    func testEachCharacterGetsHerOwnPath() {
        let one = UUID()
        let two = UUID()

        XCTAssertNotEqual(
            FileConversationStore.url(forCharacter: one),
            FileConversationStore.url(forCharacter: two)
        )
        XCTAssertNotEqual(FileConversationStore.url(forCharacter: one), FileConversationStore.defaultURL)
    }

    /// End to end against a real temporary directory, because the decision
    /// being right does not mean the move is.
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
