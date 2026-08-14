import XCTest
@testable import SecretaryCore

/// The menu bar, asserted row by row against `menu.pdf`.
///
/// This is the reason the shape was pulled out of `StatusBarController`: the
/// app target is never linked into the test bundle, so while the menu was built
/// out of `NSMenuItem`s in place, not one of its hundred-odd lines of structure
/// had ever been executed by a test.
final class StatusMenuTests: XCTestCase {
    private let miku = UUID()
    private let anya = UUID()

    private func state(
        _ id: UUID,
        _ name: String,
        visible: Bool = true,
        history: [ConversationMenuRow] = [],
        pinned: [PinnedMenuRow] = []
    ) -> CharacterMenuState {
        CharacterMenuState(id: id, name: name, isVisible: visible, history: history, pinned: pinned)
    }

    /// Walks a path of submenu titles and returns what is inside.
    private func submenu(_ entries: [StatusMenuEntry], _ path: String...) -> [StatusMenuEntry] {
        path.reduce(entries) { level, title in
            for case .item(let item) in level where item.title == title {
                return item.submenu ?? []
            }
            XCTFail("no submenu titled \(title)")
            return []
        }
    }

    private func titles(_ entries: [StatusMenuEntry]) -> [String] {
        entries.map {
            switch $0 {
            case .separator: return "—"
            case .item(let item): return item.title
            }
        }
    }

    private func item(_ entries: [StatusMenuEntry], _ title: String) -> StatusMenuItem? {
        for case .item(let item) in entries where item.title == title { return item }
        return nil
    }

    // MARK: - The shape

    /// The characters sit at the root now. They used to hang under a
    /// "Characters" row that held nothing of its own and existed to be hovered
    /// past.
    func testTheCharactersSitAtTheRootWithTheAppRows() {
        let menu = statusBarMenu(summary: "AI Secretary 0.13.209", characters: [state(miku, "Miku")])

        XCTAssertEqual(titles(menu), [
            "AI Secretary 0.13.209",
            "—",
            "Miku",
            "—",
            "Hide All",
            "New Character…",
            "—",
            "Token Usage",
            "About AI Secretary",
            "—",
            "Quit AI Secretary",
        ])
    }

    /// A label, not something to click: it answers "which build am I running"
    /// without opening anything.
    func testTheVersionHeaderIsNotClickable() {
        let menu = statusBarMenu(summary: "AI Secretary 0.13.209", characters: [])
        let header = item(menu, "AI Secretary 0.13.209")

        XCTAssertEqual(header?.isEnabled, false)
        XCTAssertNil(header?.action)
    }

    func testEveryCharacterGetsARowAndNewCharacterFollowsThem() {
        let menu = statusBarMenu(summary: "x", characters: [state(miku, "Miku"), state(anya, "Anya")])

        XCTAssertEqual(
            titles(menu).dropFirst(2).prefix(5),
            ["Miku", "Anya", "—", "Hide All", "New Character…"]
        )
    }

    /// With nobody on the desktop the row that makes somebody is still there.
    func testNewCharacterSurvivesAnEmptyRoster() {
        let menu = statusBarMenu(summary: "x", characters: [])

        XCTAssertEqual(titles(menu).dropFirst(2).first, "New Character…")
    }

    /// Clicking her name shows or hides her. It used to do nothing at all,
    /// because the row was only ever a lid on a submenu.
    func testACharacterRowBothTogglesHerAndOpensHerSubmenu() {
        let menu = statusBarMenu(summary: "x", characters: [state(miku, "Miku")])

        XCTAssertEqual(item(menu, "Miku")?.action, .toggleCharacter(character: miku))
        XCTAssertNotNil(item(menu, "Miku")?.submenu)
    }

    func testACharacterCarriesHerOwnConversationAndHerOwnPanes() {
        let menu = statusBarMenu(summary: "x", characters: [state(miku, "Miku")])

        XCTAssertEqual(titles(submenu(menu, "Miku")), [
            "Hide Character",
            "New chat",
            "Chat History",
            "—",
            "Pinned Messages",
        ])
    }

    // MARK: - What the rows say

    func testTheVisibilityRowSaysWhatClickingItWillDo() {
        let showing = statusBarMenu(summary: "x", characters: [state(miku, "Miku", visible: true)])
        let hidden = statusBarMenu(summary: "x", characters: [state(miku, "Miku", visible: false)])

        XCTAssertEqual(titles(submenu(showing, "Miku")).first, "Hide Character")
        XCTAssertEqual(titles(submenu(hidden, "Miku")).first, "Show Character")
    }

    func testAnEmptyHistoryIsGreyedAndSaysSo() {
        let menu = statusBarMenu(summary: "x", characters: [state(miku, "Miku")])

        XCTAssertEqual(item(submenu(menu, "Miku"), "Chat History")?.isEnabled, false)
        XCTAssertEqual(titles(submenu(menu, "Miku", "Chat History")), ["No past conversations"])
    }

    func testAnEmptyPinnedListIsGreyedAndSaysSo() {
        let menu = statusBarMenu(summary: "x", characters: [state(miku, "Miku")])

        XCTAssertEqual(item(submenu(menu, "Miku"), "Pinned Messages")?.isEnabled, false)
        XCTAssertEqual(titles(submenu(menu, "Miku", "Pinned Messages")), ["Nothing pinned yet"])
    }

    func testHistoryListsConversationsThenClearAll() {
        let one = UUID()
        let menu = statusBarMenu(summary: "x", characters: [
            state(miku, "Miku", history: [
                ConversationMenuRow(id: one, label: "Second Brain", isCurrent: false),
                ConversationMenuRow(id: UUID(), label: "Ask about games…", isCurrent: true),
            ]),
        ])

        XCTAssertEqual(titles(submenu(menu, "Miku", "Chat History")), [
            "Second Brain", "Ask about games…", "—", "Clear All",
        ])
        XCTAssertEqual(
            item(submenu(menu, "Miku", "Chat History"), "Second Brain")?.action,
            .resumeConversation(character: miku, conversation: one)
        )
    }

    /// Which one you are already in. Without it, reopening the conversation you
    /// are looking at is an invisible no-op that reads as the menu being broken.
    func testTheConversationYouAreInIsTicked() {
        let menu = statusBarMenu(summary: "x", characters: [
            state(miku, "Miku", history: [
                ConversationMenuRow(id: UUID(), label: "Older", isCurrent: false),
                ConversationMenuRow(id: UUID(), label: "This one", isCurrent: true),
            ]),
        ])
        let history = submenu(menu, "Miku", "Chat History")

        XCTAssertEqual(item(history, "Older")?.isChecked, false)
        XCTAssertEqual(item(history, "This one")?.isChecked, true)
    }

    func testPinnedListsPanesThenShowAllAndClearAll() {
        let pane = UUID()
        let menu = statusBarMenu(summary: "x", characters: [
            state(miku, "Miku", pinned: [PinnedMenuRow(id: pane, title: "Costs")]),
        ])

        XCTAssertEqual(titles(submenu(menu, "Miku", "Pinned Messages")), [
            "Costs", "—", "Show All", "Clear All",
        ])
        XCTAssertEqual(
            item(submenu(menu, "Miku", "Pinned Messages"), "Costs")?.action,
            .showPinned(character: miku, window: pane)
        )
    }

    // MARK: - Which character a click is about

    /// The bug this design exists to make impossible: with two characters on
    /// screen, every row has to carry whose it is, rather than the app guessing
    /// from whichever one is focused when the click lands.
    func testEveryActionNamesTheCharacterItBelongsTo() {
        let menu = statusBarMenu(summary: "x", characters: [state(miku, "Miku"), state(anya, "Anya")])

        XCTAssertEqual(
            item(submenu(menu, "Anya"), "New chat")?.action,
            .newChat(character: anya)
        )
        XCTAssertEqual(
            item(submenu(menu, "Miku"), "New chat")?.action,
            .newChat(character: miku)
        )
    }

    // MARK: - Shortcuts

    func testTheShortcutsAreAdvertisedWhereTheyAlwaysWere() {
        let menu = statusBarMenu(summary: "x", characters: [state(miku, "Miku")])

        XCTAssertEqual(item(menu, "Token Usage")?.shortcut, .commandU)
        XCTAssertEqual(item(menu, "Quit AI Secretary")?.shortcut, .commandQ)
        XCTAssertEqual(
            item(submenu(menu, "Miku"), "Hide Character")?.shortcut,
            .commandH
        )
    }
}

/// Adding up what several characters have spent, for the one usage window.
final class TotalUsageTests: XCTestCase {
    private func usage(
        turns: Int = 0,
        input: Int = 0,
        cost: Double = 0,
        window: Int? = nil,
        lastTurn: Int = 0
    ) -> SessionUsage {
        SessionUsage(
            turns: turns, inputTokens: input, outputTokens: 0,
            cacheWriteTokens: 0, cacheReadTokens: 0,
            costUSD: cost, contextWindow: window, lastTurnContextTokens: lastTurn
        )
    }

    func testNobodySpendsNothing() {
        XCTAssertEqual(totalUsage([]), .empty)
    }

    func testTheCountableFiguresAddUp() {
        let total = totalUsage([
            usage(turns: 2, input: 100, cost: 0.5),
            usage(turns: 3, input: 40, cost: 0.25),
        ])

        XCTAssertEqual(total.turns, 5)
        XCTAssertEqual(total.inputTokens, 140)
        XCTAssertEqual(total.costUSD, 0.75, accuracy: 0.0001)
    }

    /// The one that would be wrong if it summed: two 200k windows are not a
    /// 400k window, and "how full is the context" would then be measured
    /// against a size no character actually has.
    func testTheContextWindowIsTheLargestNotTheSum() {
        let total = totalUsage([usage(window: 200_000), usage(window: 1_000_000)])

        XCTAssertEqual(total.contextWindow, 1_000_000)
    }

    /// Likewise: the fullest session is the one worth knowing about. Summing
    /// would report a session nobody is in.
    func testTheLastTurnContextIsTheFullestNotTheSum() {
        let total = totalUsage([usage(lastTurn: 30_000), usage(lastTurn: 12_000)])

        XCTAssertEqual(total.lastTurnContextTokens, 30_000)
    }

    func testAnUnknownWindowDoesNotEraseAKnownOne() {
        XCTAssertEqual(totalUsage([usage(window: nil), usage(window: 200_000)]).contextWindow, 200_000)
    }
}
