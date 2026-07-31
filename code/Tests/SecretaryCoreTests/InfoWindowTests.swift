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
        XCTAssertEqual(parsed.request?.title, "Workshop agenda")
        XCTAssertTrue(parsed.request?.body.contains("| 09:00 | Intro |") == true)
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
            XCTAssertNil(parsed.request, "Should not have opened a window: \(message)")
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

    func testTheTitleIsOptional() {
        let parsed = InfoWindowBlock.parse("ok\n```window\njust the content\n```")
        XCTAssertEqual(parsed.request?.title, InfoWindowBlock.defaultTitle)
        XCTAssertEqual(parsed.request?.body, "just the content")
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
        XCTAssertEqual(parsed.request?.title, "First")
        XCTAssertEqual(parsed.request?.body, "title: this one is data")
    }

    func testAnEmptyBlockOpensNothingAndLeavesTheMessageWhole() {
        let message = "nothing\n\n```window\ntitle: Empty\n```"
        let parsed = InfoWindowBlock.parse(message)
        XCTAssertNil(parsed.request)
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
    func testTheOldestGoesOnceTheLimitIsReached() {
        var set = InfoWindowSet.empty
        for index in 1...(InfoWindowSet.limit + 3) {
            set = set.adding(spec("w\(index)"))
        }
        XCTAssertEqual(set.windows.count, InfoWindowSet.limit)
        XCTAssertEqual(set.windows.first?.title, "w4")
        XCTAssertEqual(set.windows.last?.title, "w\(InfoWindowSet.limit + 3)")
    }
}
