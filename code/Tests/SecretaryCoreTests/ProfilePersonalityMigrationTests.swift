import XCTest
@testable import SecretaryCore

/// `style` was renamed to `personality` in 0.6.126. Every profile the user
/// already had is on disk under the old key.
///
/// This is guarded rather than assumed because the failure is silent and total:
/// `ProfileStore.load()` turns any decode error into an empty selection, and
/// `ProfileLibrary` reads empty as a first launch and seeds Miku. A profile file
/// that no longer decodes doesn't raise anything — it wipes the user's
/// characters and replaces them with the built-in one.
final class ProfilePersonalityMigrationTests: XCTestCase {
    private let id = UUID(uuidString: "1D5E9C10-0000-4000-8000-000000000042")!

    private func decode(_ json: String) throws -> SecretaryProfile {
        try JSONDecoder().decode(SecretaryProfile.self, from: Data(json.utf8))
    }

    func testAProfileWrittenBeforeTheRenameStillLoads() throws {
        let profile = try decode("""
        {"id":"\(id.uuidString)","name":"อาเนีย","age":{"years":{"_0":6}},
         "gender":{"female":{}},"style":"ขี้เล่น ร่าเริง ซึนเดเระ"}
        """)
        XCTAssertEqual(profile.personality, "ขี้เล่น ร่าเริง ซึนเดเระ")
        XCTAssertEqual(profile.name, "อาเนีย")
    }

    func testTheNewKeyIsWhatGetsWritten() throws {
        let profile = SecretaryProfile(id: id, name: "Kai", personality: "ขี้เล่น")
        let json = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        XCTAssertTrue(json.contains("personality"), "Got: \(json)")
        XCTAssertFalse(json.contains("\"style\""), "The old key must not be written back")
    }

    /// Both keys present — a file written by a new build and then hand-edited,
    /// or a half-migrated one — resolves to the new spelling rather than
    /// depending on key order.
    func testTheNewKeyWinsWhenBothArePresent() throws {
        let profile = try decode("""
        {"id":"\(id.uuidString)","name":"Kai","age":{"adult":{}},
         "gender":{"other":{"_0":""}},"style":"old","personality":"new"}
        """)
        XCTAssertEqual(profile.personality, "new")
    }

    /// Neither key is a file from before the field existed at all. It must load
    /// as the default rather than failing and taking the whole library with it.
    func testAFileWithNoPersonalityAtAllFallsBackToTheDefault() throws {
        let profile = try decode("""
        {"id":"\(id.uuidString)","name":"Kai","age":{"adult":{}},
         "gender":{"other":{"_0":""}}}
        """)
        XCTAssertEqual(profile.personality, SecretaryProfile.defaultPersonality)
    }

    /// The rest of the profile is untouched by the rename — a migration that
    /// quietly dropped the picture's id or the age would be just as bad.
    func testTheOtherFieldsSurviveTheOldSpelling() throws {
        let profile = try decode("""
        {"id":"\(id.uuidString)","name":"Kai","age":{"years":{"_0":22}},
         "gender":{"other":{"_0":"non-binary"}},"style":"เป็นเพื่อน"}
        """)
        XCTAssertEqual(profile.id, id)
        XCTAssertEqual(profile.age, .years(22))
        XCTAssertEqual(profile.gender, .other("non-binary"))
    }
}
