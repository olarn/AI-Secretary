import XCTest
@testable import SecretaryCore

/// Replies routinely contain pipe tables — the shoe-price answer that prompted
/// this arrived as one. SwiftUI renders them as a wall of pipes unless they're
/// pulled out and laid out.
final class MarkdownTableTests: XCTestCase {
    private func segments(_ text: String) -> [TranscriptSegment] {
        MarkdownTableParser.segments(of: text)
    }

    private func onlyTable(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> MarkdownTable? {
        let found = segments(text).compactMap { segment -> MarkdownTable? in
            if case .table(let table) = segment { return table }
            return nil
        }
        XCTAssertEqual(found.count, 1, "Expected exactly one table", file: file, line: line)
        return found.first
    }

    func testParsesAPlainTable() {
        let table = onlyTable("""
        | Model | Price |
        |---|---|
        | Cloud 6 | 6,200 |
        | Cloudmonster 2 | 7,400 |
        """)
        XCTAssertEqual(table?.header, ["Model", "Price"])
        XCTAssertEqual(table?.rows, [["Cloud 6", "6,200"], ["Cloudmonster 2", "7,400"]])
    }

    func testKeepsProseAroundTheTableInOrder() {
        let parsed = segments("""
        Here are the prices:

        | A | B |
        | --- | --- |
        | 1 | 2 |

        Hope that helps.
        """)
        XCTAssertEqual(parsed.count, 3)
        guard case .text(let before) = parsed[0], case .table = parsed[1], case .text(let after) = parsed[2] else {
            return XCTFail("Got: \(parsed)")
        }
        XCTAssertEqual(before, "Here are the prices:")
        XCTAssertEqual(after, "Hope that helps.")
    }

    func testAcceptsAlignmentMarkersAndOuterPipesBeingOptional() {
        let table = onlyTable("""
        Name | Score
        :--- | ---:
        Ann | 10
        """)
        XCTAssertEqual(table?.header, ["Name", "Score"])
        XCTAssertEqual(table?.rows, [["Ann", "10"]])
    }

    func testHandlesThaiAndFormattedCells() {
        let table = onlyTable("""
        | กลุ่ม | ช่วงราคา |
        |---|---|
        | **รุ่นเริ่มต้น** | 6,200–6,600 |
        """)
        XCTAssertEqual(table?.header, ["กลุ่ม", "ช่วงราคา"])
        XCTAssertEqual(table?.rows.first, ["**รุ่นเริ่มต้น**", "6,200–6,600"])
    }

    // MARK: - Leaving prose alone

    /// A message is model output, not a document we control. Mangling ordinary
    /// text that happens to contain a pipe would be worse than not styling one
    /// table, so a separator row is required.
    func testAPipeInProseIsNotATable() {
        let parsed = segments("Run `ls | grep foo` to filter the list.")
        XCTAssertEqual(parsed.count, 1)
        guard case .text = parsed[0] else { return XCTFail("Prose was eaten: \(parsed)") }
    }

    func testAHeaderWithNoSeparatorStaysProse() {
        let parsed = segments("| A | B |\n| 1 | 2 |")
        XCTAssertEqual(parsed.count, 1)
        guard case .text = parsed[0] else { return XCTFail("Got: \(parsed)") }
    }

    func testASeparatorWithADifferentColumnCountIsNotATable() {
        let parsed = segments("| A | B |\n|---|\n| 1 | 2 |")
        guard case .text = parsed[0] else { return XCTFail("Got: \(parsed)") }
    }

    func testPlainTextIsUntouched() {
        XCTAssertEqual(segments("Just an answer."), [.text("Just an answer.")])
        XCTAssertEqual(segments(""), [])
    }

    // MARK: - Ragged and awkward input

    /// Generated markdown often has rows that don't match the header. Dropping
    /// or crashing on those would lose data; the grid just has to stay square.
    func testShortRowsArePaddedAndLongOnesTrimmed() {
        let table = onlyTable("""
        | A | B | C |
        |---|---|---|
        | 1 |
        | 1 | 2 | 3 | 4 |
        """)
        XCTAssertEqual(table?.rows, [["1", "", ""], ["1", "2", "3"]])
    }

    func testEmptyCellsSurvive() {
        let table = onlyTable("| A | B |\n|---|---|\n|  | 2 |")
        XCTAssertEqual(table?.rows, [["", "2"]])
    }

    func testAnEscapedPipeStaysInsideTheCell() {
        let table = onlyTable(#"""
        | Command | Note |
        |---|---|
        | a \| b | pipes |
        """#)
        XCTAssertEqual(table?.rows, [["a | b", "pipes"]])
    }

    func testATableWithNoRowsIsStillATable() {
        let table = onlyTable("| A | B |\n|---|---|")
        XCTAssertEqual(table?.header, ["A", "B"])
        XCTAssertTrue(table?.rows.isEmpty == true)
    }

    func testTwoTablesInOneMessageAreBothFound() {
        let parsed = segments("""
        | A |
        |---|
        | 1 |

        then

        | B |
        |---|
        | 2 |
        """)
        let tables = parsed.filter { if case .table = $0 { return true }; return false }
        XCTAssertEqual(tables.count, 2)
    }
}
