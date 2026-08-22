import XCTest
@testable import SecretaryCore

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

    func testAChildGetsAChildsPronoun() {
        XCTAssertTrue(profile(.female, years: 6).promptDescription.contains("หนู"))
        XCTAssertFalse(profile(.female, years: 6).promptDescription.contains("ดิฉัน"))
        XCTAssertTrue(profile(.female, years: 30).promptDescription.contains("ดิฉัน"))
    }

    func testAnUnsetGenderIsAskedToStayConsistentRatherThanPickASide() {
        let prompt = profile(.other(""), years: 45).promptDescription
        XCTAssertTrue(prompt.contains("stay consistent"))
        XCTAssertFalse(prompt.contains("never ครับ"))
        XCTAssertFalse(prompt.contains("never ค่ะ"))
    }

    func testTheRuleSaysItChangesFormAndNothingElse() {
        for gender in [SecretaryProfile.Gender.female, .male, .other("")] {
            XCTAssertTrue(
                profile(gender, years: 20).promptDescription
                    .contains("never about what you say or how much you do")
            )
        }
    }
}
