import XCTest
@testable import SecretaryCore

/// Pinning the same box twice hands back the pane you already have.
final class InfoWindowDuplicateTests: XCTestCase {
    private let spec = InfoWindowSpec(title: "อาเนีย · 15:32", body: "npm run build")

    func testAPaneHoldingTheSameThingIsFound() {
        let set = InfoWindowSet.empty.adding(spec)
        XCTAssertEqual(set.matching(title: spec.title, body: spec.body)?.id, spec.id)
    }

    /// Same title, different text — a second answer in the same minute — is a
    /// different pane and must not be mistaken for the first.
    func testADifferentBodyUnderTheSameTitleIsNotAMatch() {
        let set = InfoWindowSet.empty.adding(spec)
        XCTAssertNil(set.matching(title: spec.title, body: "npm run dev"))
    }

    /// And the same text under a different title is a different pane too: the
    /// title carries the time, which is how two panes are told apart.
    func testTheTitleIsPartOfTheMatch() {
        let set = InfoWindowSet.empty.adding(spec)
        XCTAssertNil(set.matching(title: "อาเนีย · 16:00", body: spec.body))
    }

    func testNothingMatchesInAnEmptySet() {
        XCTAssertNil(InfoWindowSet.empty.matching(title: spec.title, body: spec.body))
    }

    /// The first one wins, so repeated pinning always lands on the same window
    /// rather than walking through a row of identical ones.
    func testTheOldestMatchIsTheOneReturned() {
        let second = InfoWindowSpec(title: spec.title, body: spec.body)
        let set = InfoWindowSet.empty.adding(spec).adding(second)
        XCTAssertEqual(set.matching(title: spec.title, body: spec.body)?.id, spec.id)
    }
}
