import XCTest
@testable import SecretaryCore

/// Whose name sits above a message.
final class SpeakerLabelTests: XCTestCase {
    func testTheUserIsAlwaysMe() {
        XCTAssertEqual(speakerLabel(isMine: true, speakerName: "อาเนีย"), "Me")
        XCTAssertEqual(speakerLabel(isMine: true, speakerName: ""), "Me")
    }

    func testTheAssistantIsWhoeverWroteTheLine() {
        XCTAssertEqual(speakerLabel(isMine: false, speakerName: "Ditto"), "Ditto")
    }

    /// The whole point of storing the name: two replies written by two
    /// different profiles keep their own names, and switching profile again
    /// changes neither.
    func testTwoRepliesKeepTheirOwnNames() {
        let earlier = speakerLabel(isMine: false, speakerName: "Ditto")
        let later = speakerLabel(isMine: false, speakerName: "อาเนีย")
        XCTAssertEqual(earlier, "Ditto")
        XCTAssertEqual(later, "อาเนีย")
    }

    /// Entries from before the name was recorded have none. They must not
    /// render as an anonymous line.
    func testAMissingNameFallsBackRatherThanRenderingEmpty() {
        XCTAssertEqual(speakerLabel(isMine: false, speakerName: ""), "Secretary")
        XCTAssertEqual(speakerLabel(isMine: false, speakerName: "   "), "Secretary")
    }
}

@MainActor
final class TranscriptSpeakerNameTests: XCTestCase {
    /// The name is a fact about when the line was written, so a later profile
    /// change must not reach back and re-sign it.
    func testARecordedNameDoesNotFollowALaterProfileChange() {
        let entry = TranscriptEntry(speaker: .secretary, text: "hi", speakerName: "Ditto")
        XCTAssertEqual(speakerLabel(isMine: false, speakerName: entry.speakerName), "Ditto")
    }

    func testTheUsersOwnTurnsCarryNoName() {
        let entry = TranscriptEntry(speaker: .user, text: "hi")
        XCTAssertEqual(entry.speakerName, "")
    }
}
