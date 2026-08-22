import XCTest
@testable import SecretaryCore

final class MessagePartsTests: XCTestCase {
    private let table = MarkdownTable(header: ["a", "b"], rows: [["1", "2"]])
    private let code = CodeBlock(language: "bash", code: "ls -la")

    func testProseAloneIsOneMessage() {
        XCTAssertEqual(
            messageParts(of: [.text("hello")]),
            [.prose([.text("hello")])]
        )
    }

    func testATableBecomesItsOwnMessageBetweenTheProse() {
        let parts = messageParts(of: [.text("before"), .table(table), .text("after")])
        XCTAssertEqual(
            parts,
            [.prose([.text("before")]), .block(.table(table)), .prose([.text("after")])]
        )
    }

    func testAFencedBlockIsSplitOutTheSameWay() {
        XCTAssertEqual(
            messageParts(of: [.text("run this"), .code(code)]),
            [.prose([.text("run this")]), .block(.code(code))]
        )
    }

    func testEachBlockGetsItsOwnMessage() {
        let parts = messageParts(of: [.table(table), .code(code)])
        XCTAssertEqual(parts, [.block(.table(table)), .block(.code(code))])
    }

    func testConsecutiveProseStaysTogether() {
        XCTAssertEqual(
            messageParts(of: [.text("one"), .text("two")]),
            [.prose([.text("one"), .text("two")])]
        )
    }

    func testEmptyProseIsDropped() {
        XCTAssertEqual(
            messageParts(of: [.text("\n  \n"), .table(table), .text("")]),
            [.block(.table(table))]
        )
    }

    func testNothingInNothingOut() {
        XCTAssertEqual(messageParts(of: []), [])
    }

    func testEveryBlockSurvivesInOrder() {
        let segments: [TranscriptSegment] = [
            .text("a"), .code(code), .text("b"), .table(table), .text("c")
        ]
        let blocks = messageParts(of: segments).compactMap { part -> TranscriptSegment? in
            if case .block(let segment) = part { return segment }
            return nil
        }
        XCTAssertEqual(blocks, [.code(code), .table(table)])
    }
}
