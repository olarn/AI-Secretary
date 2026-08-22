import XCTest
@testable import SecretaryCore

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

    func testTheNewKeyWinsWhenBothArePresent() throws {
        let profile = try decode("""
        {"id":"\(id.uuidString)","name":"Kai","age":{"adult":{}},
         "gender":{"other":{"_0":""}},"style":"old","personality":"new"}
        """)
        XCTAssertEqual(profile.personality, "new")
    }

    func testAFileWithNoPersonalityAtAllFallsBackToTheDefault() throws {
        let profile = try decode("""
        {"id":"\(id.uuidString)","name":"Kai","age":{"adult":{}},
         "gender":{"other":{"_0":""}}}
        """)
        XCTAssertEqual(profile.personality, SecretaryProfile.defaultPersonality)
    }

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
