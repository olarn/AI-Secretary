import XCTest
@testable import SecretaryCore

/// One row that takes everyone off the desktop or brings everyone back, and
/// which of the two it is comes from the desktop rather than from a remembered
/// state.
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

    /// The one you can still see is the one you wanted gone. A count — "most of
    /// them are away, so this is Show" — would leave her standing there under a
    /// row that said Hide.
    func testOneCharacterStillShowingIsEnoughToKeepItHide() {
        XCTAssertEqual(title([state("Miku", visible: false), state("Anya", visible: true)]), "Hide All")
    }

    func testOnlyWithNobodyLeftDoesItOfferToBringThemBack() {
        XCTAssertEqual(title([state("Miku", visible: false), state("Anya", visible: false)]), "Show All")
    }

    /// Nobody on the desktop means nothing to hide and nothing to show, and a
    /// row that would do neither is worse than no row.
    func testAnEmptyRosterHasNoSuchRow() {
        XCTAssertNil(title([]))
    }

    /// It sits with the characters it acts on, above the row that makes a new
    /// one.
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

    /// The rule on its own, apart from the row it happens to be printed in.
    func testTheTitleIsDecidedByWhoIsVisible() {
        XCTAssertEqual(allCharactersTitle([state("a", visible: true)]), "Hide All")
        XCTAssertEqual(allCharactersTitle([state("a", visible: false)]), "Show All")
        XCTAssertEqual(allCharactersTitle([]), "Show All")
    }

    /// Toggling is one action, not two rows — so the menu can never offer both
    /// at once, and clicking always means "make the desktop the other way".
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
