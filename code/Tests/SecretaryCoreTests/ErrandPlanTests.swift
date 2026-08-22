import XCTest
@testable import SecretaryCore

final class ErrandPlanTests: XCTestCase {
    func testANumberedRequestSendsStepOneAndKeepsTheRest() {
        let parsed = stepwise("""
            1. ขอข้อมูล เปรียบเทียบราคารถมือ 2 ระหว่าง city กับ vios ปี 2020 จาก Pikachu และ Ditto
            2. เมื่อได้ข้อมูลทั้ง 2 ชุด ให้รวมข้อมูล 2 ชุด แล้วบันทึกลง file ใน project
            """)
        XCTAssertEqual(parsed?.first, "1. ขอข้อมูล เปรียบเทียบราคารถมือ 2 ระหว่าง city กับ vios ปี 2020 จาก Pikachu และ Ditto")
        XCTAssertEqual(parsed?.rest, "2. เมื่อได้ข้อมูลทั้ง 2 ชุด ให้รวมข้อมูล 2 ชุด แล้วบันทึกลง file ใน project")
    }

    func testThreeStepsKeepEverythingAfterTheFirst() {
        let parsed = stepwise("1. ask them\n2. merge it\n3. save it")
        XCTAssertEqual(parsed?.first, "1. ask them")
        XCTAssertEqual(parsed?.rest, "2. merge it\n3. save it")
    }

    func testBracketsAndColonsCountAsNumbering() {
        XCTAssertNotNil(stepwise("1) ask them\n2) save it"))
        XCTAssertNotNil(stepwise("1: ask them\n2: save it"))
    }

    func testAYearIsNotAStepNumber() {
        XCTAssertNil(stepwise("ขอข้อมูลรถ city 2015 เทียบกับ vios 2015 จาก Pikachu"))
    }

    func testOneStepIsJustAMessage() {
        XCTAssertNil(stepwise("1. ask Pikachu for the price"))
    }

    func testAnOrdinaryMessageIsNotAPlan() {
        XCTAssertNil(stepwise("ขอราคารถหน่อย"))
    }

    func testNumberingMustStartTheMessage() {
        XCTAssertNil(stepwise("here's what I want:\n1. ask them\n2. save it"))
    }

    func testTheFollowUpQuotesEveryAnswerAndRepeatsTheInstruction() {
        let prompt = followUpPrompt(
            answers: [RelayAnswer(name: "Pikachu", body: "Vios 190,000"),
                      RelayAnswer(name: "Ditto", body: "City 195,000")],
            missing: [],
            thenDo: "รวมข้อมูล แล้วบันทึกลง file"
        )
        XCTAssertTrue(prompt.contains("From Pikachu:\nVios 190,000"))
        XCTAssertTrue(prompt.contains("From Ditto:\nCity 195,000"))
        XCTAssertTrue(prompt.contains("รวมข้อมูล แล้วบันทึกลง file"))
    }

    func testAMissingAnswerIsNamedAndMustBeAdmittedInTheReply() {
        let prompt = followUpPrompt(
            answers: [RelayAnswer(name: "Pikachu", body: "Vios 190,000")],
            missing: ["Ditto"],
            thenDo: "รวมข้อมูล"
        )
        XCTAssertTrue(prompt.contains("Ditto did not answer in time"))
        XCTAssertTrue(prompt.contains("say plainly"))
        XCTAssertTrue(prompt.contains("comparison of 2"))
    }

    func testNothingIsSaidAboutMissingAnswersWhenNoneAreMissing() {
        let prompt = followUpPrompt(
            answers: [RelayAnswer(name: "Pikachu", body: "x")], missing: [], thenDo: "save it"
        )
        XCTAssertFalse(prompt.contains("did not answer"))
    }

    func testTheSentLineNamesEveryoneItWentTo() {
        XCTAssertEqual(
            relayFanOutLine(to: ["Pikachu", "Ditto"]),
            "→ Passed this on to Pikachu and Ditto. I'll say when the answers are in."
        )
    }

    func testOneRecipientKeepsTheSingularLine() {
        XCTAssertEqual(relayFanOutLine(to: ["Pikachu"]), relaySentLine(to: "Pikachu"))
    }

    func testBeingQueuedIsSaidOnBothSides() {
        XCTAssertTrue(relayQueuedHereLine(from: "Anya", ahead: 1).contains("next"))
        XCTAssertTrue(relayAcceptedLine(from: "Pikachu", ahead: 3).contains("3 along in her queue"))
        XCTAssertTrue(relayAcceptedLine(from: "Pikachu", ahead: 1).contains("Still waiting"))
    }

    func testUnreachableIsSaidAtTheMomentItBecomesTrue() {
        XCTAssertTrue(relayUnavailableLine(["Ditto"]).contains("Ditto couldn't be reached"))
        XCTAssertTrue(relayUnavailableLine(["Ditto"]).contains("not waiting on her"))
        XCTAssertTrue(relayUnavailableLine(["Ditto", "Pikachu"]).contains("not waiting on them"))
    }
}
