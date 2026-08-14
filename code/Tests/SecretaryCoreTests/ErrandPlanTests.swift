import XCTest
@testable import SecretaryCore

/// A numbered request split into what goes out now and what happens when the
/// answers are in.
final class ErrandPlanTests: XCTestCase {
    /// The owner's own example, verbatim.
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

    /// Inferring a plan from prose would turn every message containing a year
    /// into a hand-off with a follow-up nobody asked for.
    func testAYearIsNotAStepNumber() {
        XCTAssertNil(stepwise("ขอข้อมูลรถ city 2015 เทียบกับ vios 2015 จาก Pikachu"))
    }

    func testOneStepIsJustAMessage() {
        XCTAssertNil(stepwise("1. ask Pikachu for the price"))
    }

    func testAnOrdinaryMessageIsNotAPlan() {
        XCTAssertNil(stepwise("ขอราคารถหน่อย"))
    }

    /// The numbering has to start the message. A "1." buried in the middle is
    /// part of what someone is saying, not the shape of the request.
    func testNumberingMustStartTheMessage() {
        XCTAssertNil(stepwise("here's what I want:\n1. ask them\n2. save it"))
    }

    // MARK: - What the sender is asked afterwards

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

    /// Working from one answer when two were asked for, without saying so,
    /// produces a comparison of one thing presented as a comparison of two.
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

    // MARK: - The lines

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
