import XCTest
import FunctionalCore
@testable import SecretaryCore

final class DelegationIntentTests: XCTestCase {
    private let anya = CharacterCard(id: UUID(), name: "Anya", model: "Opus 5", effort: "Default")
    private let ditto = CharacterCard(id: UUID(), name: "Ditto", model: "Opus 5", effort: "Default")
    private var roster: [CharacterCard] { [anya, ditto] }

    private func read(_ text: String) -> DelegationReading {
        delegationIntent(in: text, directory: roster)
    }

    func testAHandOffPhraseWithOneNameIsActedOn() {
        guard case .confident(let to, let errand) = read("ช่วยขอให้ Anya หาราคา honda ปี 2020 ให้หน่อย") else {
            return XCTFail("expected a confident reading")
        }
        XCTAssertEqual(to.map(\.name), ["Anya"])
        XCTAssertEqual(errand, "ช่วยขอให้ Anya หาราคา honda ปี 2020 ให้หน่อย")
    }

    func testEnglishHandsOffTheSameWay() {
        guard case .confident(let to, _) = read("ask Anya to look up the price") else {
            return XCTFail("expected a confident reading")
        }
        XCTAssertEqual(to.map(\.name), ["Anya"])
    }

    func testTheErrandIsTheWholeMessage() {
        guard case .confident(_, let errand) = read("  ขอให้ Anya เช็คราคาให้หน่อย  ") else {
            return XCTFail("expected a confident reading")
        }
        XCTAssertEqual(errand, "ขอให้ Anya เช็คราคาให้หน่อย")
    }

    func testNameMatchingIgnoresCase() {
        guard case .confident(let to, _) = read("ask anya to check") else {
            return XCTFail("expected a confident reading")
        }
        XCTAssertEqual(to.map(\.name), ["Anya"])
    }

    func testAHandOffToANameWeDoNotKnowAsksWhoRatherThanAnsweringItself() {
        guard case .unsure(let candidates, let errand) = read("ช่วยขอให้อาเนีย หาราคา honda ปี 2020 ให้หน่อย") else {
            return XCTFail("expected an unsure reading, not a silent answer")
        }
        XCTAssertEqual(candidates.map(\.name), ["Anya", "Ditto"])
        XCTAssertTrue(errand.contains("honda"))
    }

    func testTwoNamesJoinedByAndNowAsksWhoRatherThanSendingToBoth() {
        guard case .unsure(let candidates, _) = read("ขอให้ Anya และ Ditto ช่วยดูราคารถมือสอง") else {
            return XCTFail("expected a question")
        }
        XCTAssertEqual(candidates.map(\.name), ["Anya", "Ditto"])
    }

    func testEnglishIsAskedAboutTheSameWay() {
        guard case .unsure(let candidates, _) = read("ask Anya and Ditto for a price comparison") else {
            return XCTFail("expected a question")
        }
        XCTAssertEqual(candidates.map(\.name), ["Anya", "Ditto"])
    }

    func testTheOwnersPriceRequestGoesToTheModel() {
        XCTAssertEqual(
            read("ขอราคา city มือ 2 เทียบกับ civic ของปี 2020 จาก Anya และ Ditto"),
            .none
        )
    }

    func testAQuestionAboutSomeoneIsNoLongerInterrupted() {
        XCTAssertEqual(read("Anya บอกว่าอะไรนะ"), .none)
        XCTAssertEqual(read("บอก Anya ว่า Ditto ทำเสร็จแล้ว"), .none)
    }

    func testTheWeakVerbsNoLongerStartAConversation() {
        for text in [
            "ขอข้อมูลราคารถมือสอง จาก Anya",
            "send Anya the file",
            "get the numbers from Ditto",
            "Anya แจ้งมาว่าเสร็จแล้ว",
            "ถาม Anya ดูแล้ว ยังไม่ตอบ"
        ] {
            XCTAssertEqual(read(text), .none, "should have gone to the model: \(text)")
        }
    }

    func testAnOrdinaryMessageIsAnOrdinaryTurn() {
        XCTAssertEqual(read("สรุปไฟล์นี้ให้หน่อย"), .none)
        XCTAssertEqual(read("what time is it"), .none)
    }

    func testMerelyNamingSomeoneDoesNotSendAnything() {
        XCTAssertEqual(read("Anya"), .none)
        XCTAssertEqual(read("Anya's window is in the way"), .none)
    }

    func testWithNobodyElseOnTheDesktopThereIsNothingToRead() {
        XCTAssertEqual(delegationIntent(in: "ขอให้ Anya ช่วยหน่อย", directory: []), .none)
    }

    func testBlankInputIsNotARequest() {
        XCTAssertEqual(read("   \n  "), .none)
    }

    func testAOneLetterNameIsNeverMatchedByAccident() {
        let tiny = CharacterCard(id: UUID(), name: "A", model: "Opus 5", effort: "Default")
        XCTAssertEqual(delegationIntent(in: "สรุปให้หน่อย", directory: [tiny]), .none)
    }

    func testACharacterWithAQualifiedNameCanBeCalledByHerFirstWord() {
        let miku = CharacterCard(
            id: UUID(), name: "Miku (Second Brain)", model: "Opus 5", effort: "Default"
        )
        guard case .confident(let to, _) = delegationIntent(
            in: "ขอให้ Miku ช่วยดูให้หน่อย", directory: [miku]
        ) else {
            return XCTFail("expected a confident reading")
        }
        XCTAssertEqual(to.map(\.name), ["Miku (Second Brain)"])
    }

    func testAThaiProfileNameIsMatchedAsWritten() {
        let anya = CharacterCard(id: UUID(), name: "อาเนีย", model: "Opus 5", effort: "Default")
        guard case .confident(let to, _) = delegationIntent(
            in: "ช่วยขอให้อาเนีย หาราคา honda ปี 2020 ให้หน่อย", directory: [anya]
        ) else {
            return XCTFail("expected a confident reading")
        }
        XCTAssertEqual(to.map(\.name), ["อาเนีย"])
    }

    func testAShortFirstWordIsNotUsedAsAName() {
        let vague = CharacterCard(id: UUID(), name: "The Assistant", model: "Opus 5", effort: "Default")
        XCTAssertEqual(namesFor(vague), ["the assistant"])
    }

    func testThereIsAlwaysAWayToSayNo() {
        XCTAssertEqual(delegationChoices([anya]), ["Anya", answerItYourselfChoice])
        XCTAssertEqual(delegationChoices(roster).last, answerItYourselfChoice)
    }

    func testSeveralNamesCanBeAnsweredWithBoth() {
        XCTAssertEqual(
            delegationChoices(roster),
            ["Anya", "Ditto", everyoneChoice, answerItYourselfChoice]
        )
    }

    func testOneNameIsNotOfferedBoth() {
        XCTAssertFalse(delegationChoices([anya]).contains(everyoneChoice))
    }

    func testTheQuestionNamesTheOneCandidateAndAsksOpenlyWhenThereAreMore() {
        XCTAssertEqual(delegationQuestion([anya]), "Should I pass this to Anya?")
        XCTAssertEqual(delegationQuestion(roster), "Who should take this?")
    }

    func testTheSameMessageReadsTheSameWayTwice() {
        let once = read("ขอให้ Anya เช็คราคาให้หน่อย")
        let twice = read("ขอให้ Anya เช็คราคาให้หน่อย")
        XCTAssertEqual(once, twice)
    }
}
