import XCTest
@testable import SecretaryCore

/// Counting what a conversation spends.
final class SessionUsageTests: XCTestCase {
    /// The real numbers from one measured turn, which is the whole reason the
    /// cache fields exist: reported as 2 in / 5 out, it actually moved 36,204
    /// tokens. Anything that folds the cache away is wrong by that much.
    private let measuredTurn = SessionUsage.empty.adding(
        inputTokens: 2,
        outputTokens: 5,
        cacheWriteTokens: 11_768,
        cacheReadTokens: 24_436,
        costUSD: 0.0780198,
        contextWindow: 1_000_000
    )

    func testTheCacheCountsAreInTheTotal() {
        XCTAssertEqual(measuredTurn.totalTokens, 36_211)
        XCTAssertNotEqual(measuredTurn.totalTokens, 7, "input + output alone is the old bug")
    }

    func testTurnsAndCostAccumulate() {
        let two = measuredTurn.adding(
            inputTokens: 10, outputTokens: 20,
            cacheWriteTokens: 0, cacheReadTokens: 100,
            costUSD: 0.02, contextWindow: 1_000_000
        )
        XCTAssertEqual(two.turns, 2)
        XCTAssertEqual(two.inputTokens, 12)
        XCTAssertEqual(two.cacheReadTokens, 24_536)
        XCTAssertEqual(two.costUSD, 0.0980198, accuracy: 0.000001)
    }

    /// Context is "how full is the window right now", so it is the last turn's
    /// reading, not a sum. Summing it would cross 100% after a few turns of a
    /// conversation that is nowhere near full.
    func testContextIsTheLastTurnNotTheSum() {
        let two = measuredTurn.adding(
            inputTokens: 3, outputTokens: 4,
            cacheWriteTokens: 0, cacheReadTokens: 50_000,
            costUSD: 0, contextWindow: 1_000_000
        )
        XCTAssertEqual(two.lastTurnContextTokens, 50_003)
        XCTAssertEqual(two.contextFraction ?? 0, 0.050003, accuracy: 0.000001)
    }

    func testContextIsUnknownUntilTheBackendSaysSo() {
        let noWindow = SessionUsage.empty.adding(
            inputTokens: 5, outputTokens: 5,
            cacheWriteTokens: 0, cacheReadTokens: 0,
            costUSD: 0, contextWindow: nil
        )
        XCTAssertNil(noWindow.contextFraction)
    }

    /// A turn that omits the window must not erase one an earlier turn reported,
    /// or the bar would blink out mid-conversation.
    func testAKnownWindowSurvivesATurnThatOmitsIt() {
        let next = measuredTurn.adding(
            inputTokens: 1, outputTokens: 1,
            cacheWriteTokens: 0, cacheReadTokens: 0,
            costUSD: 0, contextWindow: nil
        )
        XCTAssertEqual(next.contextWindow, 1_000_000)
    }

    func testTheFractionNeverExceedsOne() {
        let over = SessionUsage.empty.adding(
            inputTokens: 5_000, outputTokens: 0,
            cacheWriteTokens: 0, cacheReadTokens: 0,
            costUSD: 0, contextWindow: 1_000
        )
        XCTAssertEqual(over.contextFraction, 1)
    }

    func testAnEmptySessionSaysSoRatherThanShowingZeroes() {
        XCTAssertTrue(UsageFormat.summary(.empty).contains("No tokens used yet"))
    }

    /// A dollar figure with no explanation reads as a bill. On a subscription
    /// nothing is charged per token, so the caveat travels with the number.
    func testTheSummaryAlwaysExplainsTheDollarFigure() {
        let text = UsageFormat.summary(measuredTurn)
        XCTAssertTrue(text.contains("$0.0780"), text)
        XCTAssertTrue(text.contains(UsageFormat.costNote), text)
    }

    func testTheSummaryShowsEveryCountAndTheContext() {
        let text = UsageFormat.summary(measuredTurn)
        for expected in ["11,768", "24,436", "36,211", "1,000,000", "4%"] {
            XCTAssertTrue(text.contains(expected), "missing \(expected) in:\n\(text)")
        }
    }

    func testLargeCountsAreGrouped() {
        XCTAssertEqual(UsageFormat.tokens(1_234_567), "1,234,567")
    }
}
