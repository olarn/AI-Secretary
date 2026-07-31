import XCTest
@testable import SecretaryCore

/// Pulling a piece of the conversation out into a window that stays open.
final class InfoWindowBlockTests: XCTestCase {
    func testAMarkedBlockOpensAWindow() {
        let parsed = InfoWindowBlock.parse("""
        Here's the schedule — I've put it in its own window.

        ```window
        title: Workshop agenda
        | Time | Topic |
        | --- | --- |
        | 09:00 | Intro |
        ```
        """)
        XCTAssertEqual(parsed.requests.first?.title, "Workshop agenda")
        XCTAssertTrue(parsed.requests.first?.body.contains("| 09:00 | Intro |") == true)
        XCTAssertEqual(parsed.body, "Here's the schedule — I've put it in its own window.")
    }

    /// The reason this is marker-based. The model produces tables constantly;
    /// none of these asked for a window.
    func testOrdinaryContentOpensNothing() {
        for message in [
            "| Time | Topic |\n| --- | --- |\n| 09:00 | Intro |",
            "I'll keep that handy for you.",
            "Here's a code block:\n\n```swift\nlet x = 1\n```",
            "Pick one.\n\n```choices\nFirst\nSecond\n```"
        ] {
            let parsed = InfoWindowBlock.parse(message)
            XCTAssertTrue(parsed.requests.isEmpty, "Should not have opened a window: \(message)")
            XCTAssertEqual(parsed.body, message, "An unmarked message must pass through untouched")
        }
    }

    /// Otherwise the same content shows twice — once in the chat, once in the
    /// window — and the fence itself appears as raw text.
    func testTheBlockNeverSurvivesIntoWhatIsShown() {
        let parsed = InfoWindowBlock.parse("Done.\n\n```window\ntitle: X\nbody text\n```")
        XCTAssertFalse(parsed.body.contains("```"), parsed.body)
        XCTAssertFalse(parsed.body.contains("body text"), parsed.body)
        XCTAssertEqual(parsed.body, "Done.")
    }

    /// Reported from real use: "pin two windows" produced one, because every
    /// block was folded into a single pane and the second title was thrown away.
    func testTwoBlocksInOneReplyOpenTwoWindows() {
        let parsed = InfoWindowBlock.parse("""
        Pinning two windows now.

        ```window
        title: Alpha
        | A | B |
        | --- | --- |
        | 1 | 2 |
        ```

        ```window
        title: Beta
        a short note
        ```
        """)
        XCTAssertEqual(parsed.requests.map(\.title), ["Alpha", "Beta"])
        XCTAssertTrue(parsed.requests[0].body.contains("| 1 | 2 |"))
        XCTAssertEqual(parsed.requests[1].body, "a short note")
        XCTAssertEqual(parsed.body, "Pinning two windows now.")
        XCTAssertFalse(parsed.requests[0].body.contains("a short note"), "The panes must not be merged")
    }

    /// A reply cut off mid-block still pins what arrived, rather than dropping it.
    func testAnUnterminatedBlockStillCounts() {
        let parsed = InfoWindowBlock.parse("ok\n```window\ntitle: Half\nsome content")
        XCTAssertEqual(parsed.requests.map(\.title), ["Half"])
    }

    func testTheTitleIsOptional() {
        let parsed = InfoWindowBlock.parse("ok\n```window\njust the content\n```")
        XCTAssertEqual(parsed.requests.first?.title, InfoWindowBlock.defaultTitle)
        XCTAssertEqual(parsed.requests.first?.body, "just the content")
    }

    /// A "title:" further down is content, not a second title.
    func testOnlyTheFirstTitleLineNamesTheWindow() {
        let parsed = InfoWindowBlock.parse("""
        ok
        ```window
        title: First
        title: this one is data
        ```
        """)
        XCTAssertEqual(parsed.requests.first?.title, "First")
        XCTAssertEqual(parsed.requests.first?.body, "title: this one is data")
    }

    func testAnEmptyBlockOpensNothingAndLeavesTheMessageWhole() {
        let message = "nothing\n\n```window\ntitle: Empty\n```"
        let parsed = InfoWindowBlock.parse(message)
        XCTAssertTrue(parsed.requests.isEmpty)
        XCTAssertEqual(parsed.body, message)
    }
}

/// Keeping track of what is open.
final class InfoWindowSetTests: XCTestCase {
    private func spec(_ title: String) -> InfoWindowSpec {
        InfoWindowSpec(title: title, body: "b")
    }

    func testWindowsAreKeptInTheOrderTheyArrived() {
        let set = InfoWindowSet.empty.adding(spec("one")).adding(spec("two"))
        XCTAssertEqual(set.windows.map(\.title), ["one", "two"])
    }

    func testRemovingTakesOnlyTheOneAsked() {
        let first = spec("one")
        let set = InfoWindowSet.empty.adding(first).adding(spec("two")).removing(first.id)
        XCTAssertEqual(set.windows.map(\.title), ["two"])
    }

    func testRemovingSomethingAlreadyGoneIsHarmless() {
        let set = InfoWindowSet.empty.adding(spec("one"))
        XCTAssertEqual(set.removing(UUID()).windows.count, 1)
    }

    func testClearAllEmptiesIt() {
        XCTAssertTrue(InfoWindowSet.empty.adding(spec("one")).cleared.isEmpty)
    }

    /// A model that keeps emitting window blocks must not be able to bury the
    /// screen. The oldest goes rather than the newest being refused, since the
    /// newest is the one just asked for.
    ///
    /// Ten, set by the owner. Pinned here so the number is a decision rather
    /// than whatever the code happens to say.
    func testTheOldestGoesOnceTheLimitIsReached() {
        var set = InfoWindowSet.empty
        for index in 1...(InfoWindowSet.limit + 3) {
            set = set.adding(spec("w\(index)"))
        }
        XCTAssertEqual(InfoWindowSet.limit, 10)
        XCTAssertEqual(set.windows.count, 10)
        XCTAssertEqual(set.windows.first?.title, "w4")
        XCTAssertEqual(set.windows.last?.title, "w\(InfoWindowSet.limit + 3)")
    }
}
