import XCTest
@testable import SecretaryCore

/// The assistant's own way of asking for something to be passed on.
///
/// It exists because the alternative was measured and was a lie: with no
/// sanctioned channel, a character told her colleagues exist reached for Claude
/// Code's `SendMessage`, aimed it at a session, and reported success.
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

    /// The block has to leave the text, or it shows up as literal typing under
    /// the reply — the mistake the choices block made once already.
    func testTheBlockIsTakenOutOfWhatIsShown() {
        let parsed = HandOffBlock.parse("Asking her now.\n\n```to\nPikachu\ncheck the price\n```")
        XCTAssertEqual(parsed.body, "Asking her now.")
        XCTAssertFalse(parsed.body.contains("```"))
    }

    func testALabelledNameIsAccepted() {
        let parsed = HandOffBlock.parse("```to\nto: Pikachu\ncheck the price\n```")
        XCTAssertEqual(parsed.request?.to, ["Pikachu"])
    }

    /// The block used to take one name, so a character asked for something
    /// from two people could only reach one — and told the person she would
    /// "ask them one at a time", which was her describing the limit she had
    /// been given rather than a choice she made.
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

    /// A name that happens to contain a separator word must not be torn in two.
    func testAOneNameHeadingStaysOneName() {
        let parsed = HandOffBlock.parse("```to\nMiku (Second Brain)\ncheck it\n```")
        XCTAssertEqual(parsed.request?.to, ["Miku (Second Brain)"])
    }

    func testSeveralLinesOfMessageAllTravel() {
        let parsed = HandOffBlock.parse("```to\nPikachu\nfirst thing\nsecond thing\n```")
        XCTAssertEqual(parsed.request?.message, "first thing\nsecond thing")
    }

    /// A name with nothing to say would put "← passed this on from you" in
    /// somebody's chat above no question at all.
    func testANameWithNoMessageIsNotARequest() {
        XCTAssertNil(HandOffBlock.parse("```to\nPikachu\n```").request)
    }

    /// Marked, never inferred. Mentioning that you'll ask somebody is a
    /// sentence, and must stay one.
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
