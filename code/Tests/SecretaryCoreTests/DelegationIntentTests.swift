import XCTest
import FunctionalCore
@testable import SecretaryCore

/// Reading "have Anya do this" out of what the person typed.
///
/// The bar is not "gets it right". It is **never acts on a guess**: the only
/// reading that sends anything without asking is an unambiguous hand-off phrase
/// with exactly one name on it. Everything else that might involve someone else
/// turns into a question, and everything that doesn't stays an ordinary turn.
final class DelegationIntentTests: XCTestCase {
    private let anya = CharacterCard(id: UUID(), name: "Anya", model: "Opus 5", effort: "Default")
    private let ditto = CharacterCard(id: UUID(), name: "Ditto", model: "Opus 5", effort: "Default")
    private var roster: [CharacterCard] { [anya, ditto] }

    private func read(_ text: String) -> DelegationReading {
        delegationIntent(in: text, directory: roster)
    }

    // MARK: - Confident

    func testAHandOffPhraseWithOneNameIsActedOn() {
        guard case .confident(let to, let errand) = read("ช่วยขอให้ Anya หาราคา honda ปี 2020 ให้หน่อย") else {
            return XCTFail("expected a confident reading")
        }
        XCTAssertEqual(to.name, "Anya")
        XCTAssertEqual(errand, "ช่วยขอให้ Anya หาราคา honda ปี 2020 ให้หน่อย")
    }

    func testEnglishHandsOffTheSameWay() {
        guard case .confident(let to, _) = read("ask Anya to look up the price") else {
            return XCTFail("expected a confident reading")
        }
        XCTAssertEqual(to.name, "Anya")
    }

    /// The whole sentence travels, uncut. Cutting "ช่วยขอให้อาเนีย" off the front
    /// is surgery on a language without spaces, and the recipient reads the
    /// request better intact than as a stump.
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
        XCTAssertEqual(to.name, "Anya")
    }

    // MARK: - Unsure — the case the whole enum exists for

    /// The owner's own scenario writes **อาเนีย** for a character whose profile
    /// name is **Anya**. Name matching finds nothing. Reading that as "nothing
    /// to do with anyone else" would answer it as the character it was typed at,
    /// which the person would read as the feature being broken — so it asks.
    func testAHandOffToANameWeDoNotKnowAsksWhoRatherThanAnsweringItself() {
        guard case .unsure(let candidates, let errand) = read("ช่วยขอให้อาเนีย หาราคา honda ปี 2020 ให้หน่อย") else {
            return XCTFail("expected an unsure reading, not a silent answer")
        }
        XCTAssertEqual(candidates.map(\.name), ["Anya", "Ditto"])
        XCTAssertTrue(errand.contains("honda"))
    }

    func testTwoNamesInOneSentenceAsksWhichOne() {
        guard case .unsure(let candidates, _) = read("ขอให้ Anya กับ Ditto ช่วยดูให้หน่อย") else {
            return XCTFail("expected an unsure reading")
        }
        XCTAssertEqual(candidates.map(\.name), ["Anya", "Ditto"])
    }

    /// "อาเนียบอกว่าอะไรนะ" is a question *about* her, not a request to send her
    /// anything, and no wording separates the two. A name plus a weak verb is
    /// worth a question and no more.
    func testANameWithAWeakVerbAsksRatherThanSends() {
        guard case .unsure(let candidates, _) = read("Anya บอกว่าอะไรนะ") else {
            return XCTFail("expected an unsure reading")
        }
        XCTAssertEqual(candidates.map(\.name), ["Anya"])
    }

    // MARK: - None

    func testAnOrdinaryMessageIsAnOrdinaryTurn() {
        XCTAssertEqual(read("สรุปไฟล์นี้ให้หน่อย"), .none)
        XCTAssertEqual(read("what time is it"), .none)
    }

    /// Mentioning someone is not an instruction to involve her.
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

    /// A one-character name would match nearly every Thai sentence, since Thai
    /// runs without spaces and matching has to be by substring.
    func testAOneLetterNameIsNeverMatchedByAccident() {
        let tiny = CharacterCard(id: UUID(), name: "A", model: "Opus 5", effort: "Default")
        XCTAssertEqual(delegationIntent(in: "สรุปให้หน่อย", directory: [tiny]), .none)
    }

    // MARK: - The way out

    /// A false positive on `ขอให้` — which appears in sentences that have
    /// nothing to do with anyone else — must not leave the person with no
    /// option but to send work somewhere they never meant to.
    func testThereIsAlwaysAWayToSayNo() {
        XCTAssertEqual(delegationChoices([anya]), ["Anya", answerItYourselfChoice])
        XCTAssertEqual(delegationChoices(roster).last, answerItYourselfChoice)
    }

    func testTheQuestionNamesTheOneCandidateAndAsksOpenlyWhenThereAreMore() {
        XCTAssertEqual(delegationQuestion([anya]), "Should I pass this to Anya?")
        XCTAssertEqual(delegationQuestion(roster), "Who should take this?")
    }

    // MARK: - Determinism

    /// Same text, same roster, same answer — twice, per the skill's rule. There
    /// is no clock and no id minted in here, and this is how that is checked.
    func testTheSameMessageReadsTheSameWayTwice() {
        let once = read("ขอให้ Anya เช็คราคาให้หน่อย")
        let twice = read("ขอให้ Anya เช็คราคาให้หน่อย")
        XCTAssertEqual(once, twice)
    }
}
