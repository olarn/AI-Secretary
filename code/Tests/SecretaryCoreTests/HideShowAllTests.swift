import XCTest
@testable import SecretaryCore

final class HideShowAllTests: XCTestCase {
    private func state(_ name: String, visible: Bool) -> CharacterMenuState {
        CharacterMenuState(id: UUID(), name: name, isVisible: visible)
    }

    private func title(_ characters: [CharacterMenuState]) -> String? {
        for case .item(let item) in statusBarMenu(summary: "x", characters: characters)
        where item.action == .toggleAllCharacters { return item.title }
        return nil
    }

    func testWithEveryoneOnScreenTheRowHides() {
        XCTAssertEqual(title([state("Miku", visible: true), state("Anya", visible: true)]), "Hide All")
    }

    func testOneCharacterStillShowingIsEnoughToKeepItHide() {
        XCTAssertEqual(title([state("Miku", visible: false), state("Anya", visible: true)]), "Hide All")
    }

    func testOnlyWithNobodyLeftDoesItOfferToBringThemBack() {
        XCTAssertEqual(title([state("Miku", visible: false), state("Anya", visible: false)]), "Show All")
    }

    func testAnEmptyRosterHasNoSuchRow() {
        XCTAssertNil(title([]))
    }

    func testItComesAfterTheCharactersAndBeforeNewCharacter() {
        let menu = statusBarMenu(summary: "x", characters: [state("Miku", visible: true)])
        let titles = menu.compactMap { entry -> String? in
            if case .item(let item) = entry { return item.title }
            return nil
        }
        let all = titles.firstIndex(of: "Hide All")
        XCTAssertNotNil(all)
        XCTAssertEqual(titles.firstIndex(of: "Miku").map { $0 + 1 }, all)
        XCTAssertEqual(all.map { $0 + 1 }, titles.firstIndex(of: "New Character…"))
    }

    func testALineSeparatesItFromTheCharacterRows() {
        let menu = statusBarMenu(
            summary: "x",
            characters: [state("Miku", visible: true), state("Anya", visible: true)]
        )
        guard let row = menu.firstIndex(where: {
            if case .item(let item) = $0 { return item.action == .toggleAllCharacters }
            return false
        }) else { return XCTFail("no Hide All row") }

        XCTAssertEqual(menu[row - 1], .separator)
    }

    func testTheLineGoesWithTheRowOnAnEmptyRoster() {
        let menu = statusBarMenu(summary: "x", characters: [])
        let titles = menu.map { entry -> String in
            if case .item(let item) = entry { return item.title }
            return "—"
        }
        XCTAssertEqual(Array(titles.prefix(3)), ["x", "—", "New Character…"])
    }

    func testTheTitleIsDecidedByWhoIsVisible() {
        XCTAssertEqual(allCharactersTitle([state("a", visible: true)]), "Hide All")
        XCTAssertEqual(allCharactersTitle([state("a", visible: false)]), "Show All")
        XCTAssertEqual(allCharactersTitle([]), "Show All")
    }

    func testThereIsOnlyEverOneSuchRow() {
        let menu = statusBarMenu(
            summary: "x",
            characters: [state("Miku", visible: true), state("Anya", visible: false)]
        )
        let rows = menu.filter {
            if case .item(let item) = $0 { return item.action == .toggleAllCharacters }
            return false
        }
        XCTAssertEqual(rows.count, 1)
    }
}
