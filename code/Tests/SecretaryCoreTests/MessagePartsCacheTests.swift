import XCTest
@testable import SecretaryCore

final class MessagePartsCacheTests: XCTestCase {
    func testTheSameMessageIsParsedOnce() {
        let cache = MessagePartsCache()
        let id = UUID()

        let first = cache.parts(id: id, text: "Hello there")
        let second = cache.parts(id: id, text: "Hello there")

        XCTAssertEqual(cache.misses, 1)
        XCTAssertEqual(cache.hits, 1)
        XCTAssertEqual(first.count, second.count)
    }

    func testAMessageStillGrowingIsParsedAgain() {
        let cache = MessagePartsCache()
        let id = UUID()

        _ = cache.parts(id: id, text: "Hel")
        _ = cache.parts(id: id, text: "Hello")

        XCTAssertEqual(cache.misses, 2, "The text differs — the old answer is not the answer")
        XCTAssertEqual(cache.hits, 0)
    }

    func testOnlyTheGrowingMessageIsReparsedAcrossTokens() {
        let cache = MessagePartsCache()
        let settled = (0..<5).map { _ in UUID() }
        let growing = UUID()

        (1...20).forEach { token in
            settled.forEach { _ = cache.parts(id: $0, text: "a finished message") }
            _ = cache.parts(id: growing, text: String(repeating: "x", count: token))
        }

        XCTAssertEqual(cache.misses, 5 + 20, "Five first sightings, then one per token")
        XCTAssertEqual(cache.hits, 5 * 19)
    }

    func testTheAnswerIsTheSameAsParsingDirectly() {
        let cache = MessagePartsCache()
        let text = "before\n\nname,qty\nnut,3\nbolt,4\n\nafter"

        let cached = cache.parts(id: UUID(), text: text)
        let direct = messageParts(of: DelimitedTableParser.segments(of: displayBody(of: text)))

        XCTAssertEqual(cached.count, direct.count)
        XCTAssertEqual(cached.count, 3, "prose, table, prose")
    }

    func testMessagesNoLongerInTheConversationAreForgotten() {
        let cache = MessagePartsCache()
        let kept = UUID()
        let dropped = UUID()
        _ = cache.parts(id: kept, text: "still here")
        _ = cache.parts(id: dropped, text: "gone with the old conversation")

        cache.keepingOnly([kept])
        _ = cache.parts(id: kept, text: "still here")
        _ = cache.parts(id: dropped, text: "gone with the old conversation")

        XCTAssertEqual(cache.hits, 1, "Only the message still on screen was remembered")
        XCTAssertEqual(cache.misses, 3)
    }

    func testTheChoicesBlockIsNotShown() {
        let text = "Which one?\n\n```choices\nA. left\nB. right\n```"
        XCTAssertFalse(displayBody(of: text).contains("```choices"))
    }
}
