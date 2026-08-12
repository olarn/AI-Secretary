import XCTest
@testable import SecretaryCore

/// What `New Character…` produces, and where she stands.
final class NewCharacterTests: XCTestCase {
    private func profile(_ name: String) -> SecretaryProfile {
        SecretaryProfile(name: name)
    }

    // MARK: - Naming

    func testAFreeNameIsUsedAsItIs() {
        XCTAssertEqual(unusedCharacterName(basedOn: "Anya", existing: [profile("Miku")]), "Anya")
    }

    /// Two characters called the same thing is not cosmetic: the menu shows two
    /// identical rows and neither says which is which.
    func testATakenNameGetsTheFirstFreeNumber() {
        XCTAssertEqual(unusedCharacterName(basedOn: "Miku", existing: [profile("Miku")]), "Miku 2")
    }

    func testItSkipsNumbersAlreadyInUse() {
        let existing = [profile("Miku"), profile("Miku 2"), profile("Miku 3")]
        XCTAssertEqual(unusedCharacterName(basedOn: "Miku", existing: existing), "Miku 4")
    }

    /// Cloning a clone must not stack suffixes.
    func testCloningACopyCountsFromTheOriginalName() {
        let existing = [profile("Miku"), profile("Miku 2")]
        XCTAssertEqual(unusedCharacterName(basedOn: "Miku 2", existing: existing), "Miku 3")
    }

    func testAGapInTheNumbersIsFilled() {
        let existing = [profile("Miku"), profile("Miku 3")]
        XCTAssertEqual(unusedCharacterName(basedOn: "Miku", existing: existing), "Miku 2")
    }

    /// A name that merely ends in a word, not a number, is left whole.
    func testANameEndingInAWordIsNotTreatedAsACopy() {
        XCTAssertEqual(
            unusedCharacterName(basedOn: "Miku Hatsune", existing: [profile("Miku Hatsune")]),
            "Miku Hatsune 2"
        )
    }

    // MARK: - What she inherits

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

    // MARK: - Where she stands

    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let visible = CGRect(x: 0, y: 54, width: 1728, height: 1030)
    private let size = CGSize(width: 128, height: 149)

    func testTheFirstCharacterStandsWhereSheAlwaysDid() {
        XCTAssertEqual(
            CharacterLaunch.origin(ordinal: 0, characterSize: size, visibleFrame: visible, screenFrame: screen),
            CharacterLaunch.origin(characterSize: size, visibleFrame: visible, screenFrame: screen)
        )
    }

    /// Landing a new character exactly on top of an existing one looks like
    /// nothing happened, which is the worst possible answer to "New Character…".
    func testEachFurtherCharacterStandsClearOfTheOneBefore() {
        let first = CharacterLaunch.origin(ordinal: 0, characterSize: size, visibleFrame: visible, screenFrame: screen)
        let second = CharacterLaunch.origin(ordinal: 1, characterSize: size, visibleFrame: visible, screenFrame: screen)
        let third = CharacterLaunch.origin(ordinal: 2, characterSize: size, visibleFrame: visible, screenFrame: screen)

        XCTAssertLessThan(second.x, first.x)
        XCTAssertLessThan(third.x, second.x)
        XCTAssertGreaterThanOrEqual(first.x - second.x, size.width)
        XCTAssertEqual(second.y, first.y)
    }

    /// The row runs out before the desktop does. Stacking at the edge is worse
    /// than a tidy row and much better than a character that cannot be clicked.
    func testTheRowStopsAtTheLeftEdgeRatherThanWalkingOffIt() {
        let far = CharacterLaunch.origin(
            ordinal: 50,
            characterSize: size,
            visibleFrame: visible,
            screenFrame: screen
        )

        XCTAssertEqual(far.x, screen.minX)
    }
}
