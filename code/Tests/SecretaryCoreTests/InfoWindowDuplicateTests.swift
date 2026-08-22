import XCTest
@testable import SecretaryCore

final class InfoWindowDuplicateTests: XCTestCase {
    private let spec = InfoWindowSpec(title: "อาเนีย · 15:32", body: "npm run build")

    func testAPaneHoldingTheSameThingIsFound() {
        let set = InfoWindowSet.empty.adding(spec)
        XCTAssertEqual(set.matching(title: spec.title, body: spec.body)?.id, spec.id)
    }

    func testADifferentBodyUnderTheSameTitleIsNotAMatch() {
        let set = InfoWindowSet.empty.adding(spec)
        XCTAssertNil(set.matching(title: spec.title, body: "npm run dev"))
    }

    func testTheTitleIsPartOfTheMatch() {
        let set = InfoWindowSet.empty.adding(spec)
        XCTAssertNil(set.matching(title: "อาเนีย · 16:00", body: spec.body))
    }

    func testNothingMatchesInAnEmptySet() {
        XCTAssertNil(InfoWindowSet.empty.matching(title: spec.title, body: spec.body))
    }

    func testTheOldestMatchIsTheOneReturned() {
        let second = InfoWindowSpec(title: spec.title, body: spec.body)
        let set = InfoWindowSet.empty.adding(spec).adding(second)
        XCTAssertEqual(set.matching(title: spec.title, body: spec.body)?.id, spec.id)
    }
}
