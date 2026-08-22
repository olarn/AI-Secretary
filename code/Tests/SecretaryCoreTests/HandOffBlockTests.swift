import XCTest
@testable import SecretaryCore

final class HandOffBlockTests: XCTestCase {
    func testANameAndAMessageIsARequest() {
        let parsed = HandOffBlock.parse("""
            Right, I'll ask her.

            ```to
            Pikachu
            หาราคา civic 2015 เทียบกับ vios 2015 ให้หน่อย
            ```
            """)
        XCTAssertEqual(parsed.request?.to, ["Pikachu"])
        XCTAssertEqual(parsed.request?.message, "หาราคา civic 2015 เทียบกับ vios 2015 ให้หน่อย")
    }

    func testTheBlockIsTakenOutOfWhatIsShown() {
        let parsed = HandOffBlock.parse("Asking her now.\n\n```to\nPikachu\ncheck the price\n```")
        XCTAssertEqual(parsed.body, "Asking her now.")
        XCTAssertFalse(parsed.body.contains("```"))
    }

    func testALabelledNameIsAccepted() {
        let parsed = HandOffBlock.parse("```to\nto: Pikachu\ncheck the price\n```")
        XCTAssertEqual(parsed.request?.to, ["Pikachu"])
    }

    func testSeveralNamesOnOneLineAllGetIt() {
        for heading in ["Pikachu, Ditto", "Pikachu และ Ditto", "Pikachu and Ditto", "Pikachu กับ Ditto"] {
            let parsed = HandOffBlock.parse("```to\n\(heading)\ncheck the price\n```")
            XCTAssertEqual(parsed.request?.to, ["Pikachu", "Ditto"], "heading: \(heading)")
        }
    }

    func testAThreeWayListSplitsToo() {
        let parsed = HandOffBlock.parse("```to\nPikachu, Ditto และ Miku\ncheck it\n```")
        XCTAssertEqual(parsed.request?.to, ["Pikachu", "Ditto", "Miku"])
    }

    func testAOneNameHeadingStaysOneName() {
        let parsed = HandOffBlock.parse("```to\nMiku (Second Brain)\ncheck it\n```")
        XCTAssertEqual(parsed.request?.to, ["Miku (Second Brain)"])
    }

    func testSeveralLinesOfMessageAllTravel() {
        let parsed = HandOffBlock.parse("```to\nPikachu\nfirst thing\nsecond thing\n```")
        XCTAssertEqual(parsed.request?.message, "first thing\nsecond thing")
    }

    func testANameWithNoMessageIsNotARequest() {
        XCTAssertNil(HandOffBlock.parse("```to\nPikachu\n```").request)
    }

    func testTalkingAboutAskingSomebodyIsNotAsking() {
        let parsed = HandOffBlock.parse("I could ask Pikachu to look that up if you like.")
        XCTAssertNil(parsed.request)
        XCTAssertEqual(parsed.body, "I could ask Pikachu to look that up if you like.")
    }

    func testAnOrdinaryReplyIsUntouched() {
        let parsed = HandOffBlock.parse("The price is about 420,000 baht.")
        XCTAssertNil(parsed.request)
        XCTAssertEqual(parsed.body, "The price is about 420,000 baht.")
    }
}
