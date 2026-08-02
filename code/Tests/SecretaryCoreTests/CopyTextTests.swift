import XCTest
@testable import SecretaryCore

/// What one box's copy button puts on the clipboard.
final class CopyTextTests: XCTestCase {
    private let table = MarkdownTable(header: ["Command", "What"], rows: [["`npm run dev`", "dev server"]])

    func testProseComesBackAsItReads() {
        XCTAssertEqual(copyText(of: .prose([.text("hello there")])), "hello there")
    }

    func testSeveralProseRunsAreJoinedByLines() {
        XCTAssertEqual(copyText(of: .prose([.text("one"), .text("two")])), "one\ntwo")
    }

    /// The blank lines the parser leaves around a paragraph shouldn't arrive on
    /// the clipboard.
    func testProseIsTrimmed() {
        XCTAssertEqual(copyText(of: .prose([.text("\n  hi  \n\n")])), "hi")
    }

    /// The command alone — no fence, no language line. What you want from a
    /// shell command is something you can paste into a shell.
    func testCodeComesBackWithoutItsFence() {
        let block = CodeBlock(language: "bash", code: "npm run dev")
        XCTAssertEqual(copyText(of: .block(.code(block))), "npm run dev")
    }

    /// A table is rebuilt as markdown: the parser keeps rows and cells, not the
    /// original text, and markdown is what pastes usefully elsewhere.
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

    /// Round trip: what the copy button produces parses back into the same
    /// table. A rebuild that quietly loses a column would still look right in a
    /// screenshot.
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
