import XCTest
@testable import SecretaryCore

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
            "Show Command",
            "—",
            "Token Usage",
            "About AI Secretary",
            "—",
            "Quit AI Secretary",
        ])
    }

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

    func testTheCommandRowSitsBetweenNewCharacterAndTokenUsage() {
        let hidden = statusBarMenu(summary: "x", characters: [state(miku, "Miku")])
        let showing = statusBarMenu(
            summary: "x",
            characters: [state(miku, "Miku")],
            isCommandWindowVisible: true
        )

        XCTAssertTrue(isSublist(["New Character…", "—", "Show Command", "—", "Token Usage"], of: titles(hidden)))
        XCTAssertTrue(isSublist(["New Character…", "—", "Hide Command", "—", "Token Usage"], of: titles(showing)))
        XCTAssertEqual(item(hidden, "Show Command")?.action, .toggleCommandWindow)
        XCTAssertEqual(item(showing, "Hide Command")?.action, .toggleCommandWindow)
    }

    private func isSublist(_ needle: [String], of haystack: [String]) -> Bool {
        haystack.indices.contains { start in
            Array(haystack[start...].prefix(needle.count)) == needle
        }
    }

    func testNewCharacterSurvivesAnEmptyRoster() {
        let menu = statusBarMenu(summary: "x", characters: [])

        XCTAssertEqual(titles(menu).dropFirst(2).first, "New Character…")
    }

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

    func testCommandHIsAdvertisedOnTheRowThatTakesEverything() {
        let menu = statusBarMenu(summary: "x", characters: [state(miku, "Miku")])

        XCTAssertEqual(item(menu, "Token Usage")?.shortcut, .commandU)
        XCTAssertEqual(item(menu, "Quit AI Secretary")?.shortcut, .commandQ)
        XCTAssertEqual(item(menu, "Hide All")?.shortcut, .commandH)
        XCTAssertNil(
            item(submenu(menu, "Miku"), "Hide Character")?.shortcut,
            "One character is a click, not ⌘H — advertising it here is the bug"
        )
    }
}

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

    func testTheContextWindowIsTheLargestNotTheSum() {
        let total = totalUsage([usage(window: 200_000), usage(window: 1_000_000)])

        XCTAssertEqual(total.contextWindow, 1_000_000)
    }

    func testTheLastTurnContextIsTheFullestNotTheSum() {
        let total = totalUsage([usage(lastTurn: 30_000), usage(lastTurn: 12_000)])

        XCTAssertEqual(total.lastTurnContextTokens, 30_000)
    }

    func testAnUnknownWindowDoesNotEraseAKnownOne() {
        XCTAssertEqual(totalUsage([usage(window: nil), usage(window: 200_000)]).contextWindow, 200_000)
    }
}
