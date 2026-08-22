import XCTest
@testable import SecretaryCore

final class CopyTextTests: XCTestCase {
    private let table = MarkdownTable(header: ["Command", "What"], rows: [["`npm run dev`", "dev server"]])

    func testProseComesBackAsItReads() {
        XCTAssertEqual(copyText(of: .prose([.text("hello there")])), "hello there")
    }

    func testSeveralProseRunsAreJoinedByLines() {
        XCTAssertEqual(copyText(of: .prose([.text("one"), .text("two")])), "one\ntwo")
    }

    func testProseIsTrimmed() {
        XCTAssertEqual(copyText(of: .prose([.text("\n  hi  \n\n")])), "hi")
    }

    func testCodeComesBackWithoutItsFence() {
        let block = CodeBlock(language: "bash", code: "npm run dev")
        XCTAssertEqual(copyText(of: .block(.code(block))), "npm run dev")
    }

    func testATableComesBackAsMarkdown() {
        XCTAssertEqual(
            copyText(of: .block(.table(table))),
            """
            | Command | What |
            | --- | --- |
            | `npm run dev` | dev server |
            """
        )
    }

    func testTheRebuiltMarkdownParsesBackIntoTheSameTable() {
        let segments = MarkdownTableParser.segments(of: markdownText(of: table))
        XCTAssertEqual(segments, [.table(table)])
    }

    func testTheDividerHasOneCellPerColumn() {
        let wide = MarkdownTable(header: ["a", "b", "c", "d"], rows: [])
        let divider = markdownText(of: wide).components(separatedBy: "\n")[1]
        XCTAssertEqual(divider, "| --- | --- | --- | --- |")
    }
}
