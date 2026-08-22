import XCTest
@testable import SecretaryCore

final class SpeakerLabelTests: XCTestCase {
    func testTheUserIsAlwaysMe() {
        XCTAssertEqual(speakerLabel(isMine: true, speakerName: "อาเนีย"), "Me")
        XCTAssertEqual(speakerLabel(isMine: true, speakerName: ""), "Me")
    }

    func testTheAssistantIsWhoeverWroteTheLine() {
        XCTAssertEqual(speakerLabel(isMine: false, speakerName: "Ditto"), "Ditto")
    }

    func testTwoRepliesKeepTheirOwnNames() {
        let earlier = speakerLabel(isMine: false, speakerName: "Ditto")
        let later = speakerLabel(isMine: false, speakerName: "อาเนีย")
        XCTAssertEqual(earlier, "Ditto")
        XCTAssertEqual(later, "อาเนีย")
    }

    func testAMissingNameFallsBackRatherThanRenderingEmpty() {
        XCTAssertEqual(speakerLabel(isMine: false, speakerName: ""), "Secretary")
        XCTAssertEqual(speakerLabel(isMine: false, speakerName: "   "), "Secretary")
    }
}

@MainActor
final class TranscriptSpeakerNameTests: XCTestCase {
    func testARecordedNameDoesNotFollowALaterProfileChange() {
        let entry = TranscriptEntry(speaker: .secretary, text: "hi", speakerName: "Ditto")
        XCTAssertEqual(speakerLabel(isMine: false, speakerName: entry.speakerName), "Ditto")
    }

    func testTheUsersOwnTurnsCarryNoName() {
        let entry = TranscriptEntry(speaker: .user, text: "hi")
        XCTAssertEqual(entry.speakerName, "")
    }
}
