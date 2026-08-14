import XCTest
@testable import SecretaryCore

/// Being "a teenage girl" in an English descriptor does not, on its own, make a
/// model close a Thai sentence with ค่ะ.
///
/// Miku was set female and answered ครับ, while อาเนีย — also female — answered
/// ค่ะ. Nothing was choosing between them: ครับ is simply where a model lands
/// when no one says otherwise. The gender was in the prompt all along; the
/// consequence of it was not.
final class GenderedSpeechTests: XCTestCase {
    private func profile(_ gender: SecretaryProfile.Gender, years: Int) -> SecretaryProfile {
        SecretaryProfile(name: "Test", age: .years(years), gender: gender, personality: "")
    }

    func testAWomanIsToldWhichThaiFormsAreHers() {
        let prompt = profile(.female, years: 17).promptDescription
        XCTAssertTrue(prompt.contains("ค่ะ"))
        XCTAssertTrue(prompt.contains("never ครับ"))
    }

    func testAManIsToldTheOppositePair() {
        let prompt = profile(.male, years: 17).promptDescription
        XCTAssertTrue(prompt.contains("ครับ"))
        XCTAssertTrue(prompt.contains("never ค่ะ"))
        XCTAssertTrue(prompt.contains("ผม"))
    }

    /// Thai pronouns are not only gendered — a six-year-old saying ดิฉัน reads
    /// as a costume.
    func testAChildGetsAChildsPronoun() {
        XCTAssertTrue(profile(.female, years: 6).promptDescription.contains("หนู"))
        XCTAssertFalse(profile(.female, years: 6).promptDescription.contains("ดิฉัน"))
        XCTAssertTrue(profile(.female, years: 30).promptDescription.contains("ดิฉัน"))
    }

    /// Unset means unset — not "pick a different one each message".
    func testAnUnsetGenderIsAskedToStayConsistentRatherThanPickASide() {
        let prompt = profile(.other(""), years: 45).promptDescription
        XCTAssertTrue(prompt.contains("stay consistent"))
        XCTAssertFalse(prompt.contains("never ครับ"))
        XCTAssertFalse(prompt.contains("never ค่ะ"))
    }

    /// It is a rule about the shape of the words, not a licence to do less.
    func testTheRuleSaysItChangesFormAndNothingElse() {
        for gender in [SecretaryProfile.Gender.female, .male, .other("")] {
            XCTAssertTrue(
                profile(gender, years: 20).promptDescription
                    .contains("never about what you say or how much you do")
            )
        }
    }
}
