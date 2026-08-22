import XCTest
@testable import SecretaryCore

final class NewCharacterTests: XCTestCase {
    private func profile(_ name: String) -> SecretaryProfile {
        SecretaryProfile(name: name)
    }

    func testAFreeNameIsUsedAsItIs() {
        XCTAssertEqual(unusedCharacterName(basedOn: "Anya", existing: [profile("Miku")]), "Anya")
    }

    func testATakenNameGetsTheFirstFreeNumber() {
        XCTAssertEqual(unusedCharacterName(basedOn: "Miku", existing: [profile("Miku")]), "Miku 2")
    }

    func testItSkipsNumbersAlreadyInUse() {
        let existing = [profile("Miku"), profile("Miku 2"), profile("Miku 3")]
        XCTAssertEqual(unusedCharacterName(basedOn: "Miku", existing: existing), "Miku 4")
    }

    func testCloningACopyCountsFromTheOriginalName() {
        let existing = [profile("Miku"), profile("Miku 2")]
        XCTAssertEqual(unusedCharacterName(basedOn: "Miku 2", existing: existing), "Miku 3")
    }

    func testAGapInTheNumbersIsFilled() {
        let existing = [profile("Miku"), profile("Miku 3")]
        XCTAssertEqual(unusedCharacterName(basedOn: "Miku", existing: existing), "Miku 2")
    }

    func testANameEndingInAWordIsNotTreatedAsACopy() {
        XCTAssertEqual(
            unusedCharacterName(basedOn: "Miku Hatsune", existing: [profile("Miku Hatsune")]),
            "Miku Hatsune 2"
        )
    }

    func testSheInheritsWhoTheTemplateIsButNotItsIdentity() {
        let template = SecretaryProfile(
            name: "Miku",
            age: .years(17),
            gender: .female,
            personality: "รอบคอบ"
        )

        let fresh = newCharacterDraft(from: template, existing: [template])

        XCTAssertEqual(fresh.age, template.age)
        XCTAssertEqual(fresh.gender, template.gender)
        XCTAssertEqual(fresh.personality, template.personality)
        XCTAssertNotEqual(fresh.id, template.id)
        XCTAssertEqual(fresh.name, "Miku 2")
    }

    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let visible = CGRect(x: 0, y: 54, width: 1728, height: 1030)
    private let size = CGSize(width: 128, height: 149)

    func testTheFirstCharacterStandsWhereSheAlwaysDid() {
        XCTAssertEqual(
            CharacterLaunch.origin(ordinal: 0, characterSize: size, visibleFrame: visible, screenFrame: screen),
            CharacterLaunch.origin(characterSize: size, visibleFrame: visible, screenFrame: screen)
        )
    }

    func testEachFurtherCharacterStandsClearOfTheOneBefore() {
        let first = CharacterLaunch.origin(ordinal: 0, characterSize: size, visibleFrame: visible, screenFrame: screen)
        let second = CharacterLaunch.origin(ordinal: 1, characterSize: size, visibleFrame: visible, screenFrame: screen)
        let third = CharacterLaunch.origin(ordinal: 2, characterSize: size, visibleFrame: visible, screenFrame: screen)

        XCTAssertLessThan(second.x, first.x)
        XCTAssertLessThan(third.x, second.x)
        XCTAssertGreaterThanOrEqual(first.x - second.x, size.width)
        XCTAssertEqual(second.y, first.y)
    }

    func testTheRowStopsAtTheLeftEdgeRatherThanWalkingOffIt() {
        let far = CharacterLaunch.origin(
            ordinal: 50,
            characterSize: size,
            visibleFrame: visible,
            screenFrame: screen
        )

        XCTAssertEqual(far.x, screen.minX)
    }

    func testTheDefaultCharacterNameIsANonEmptyStem() {
        XCTAssertEqual(defaultNewCharacterName, "Secretary")
    }
}
