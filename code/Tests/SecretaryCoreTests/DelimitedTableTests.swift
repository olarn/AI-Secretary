import FunctionalCore
import XCTest
@testable import SecretaryCore

/// Pasted rows, read as a grid.
///
/// Both directions matter and the wrong one is worse: failing to lay out a CSV
/// costs a wall of commas, while laying out an ordinary paragraph as a grid
/// makes the person's own words unreadable. So the tests below spend more of
/// their weight on what must *not* become a table.
final class DelimitedTableTests: XCTestCase {

    private func tables(_ text: String) -> [MarkdownTable] {
        DelimitedTableParser.segments(of: text).compactMap {
            if case .table(let table) = $0 { return table }
            return nil
        }
    }

    private func prose(_ text: String) -> [String] {
        DelimitedTableParser.segments(of: text).compactMap {
            if case .text(let body) = $0 { return body }
            return nil
        }
    }

    func testAPastedCsvBecomesATable() {
        let table = tables("name,email\nAda,ada@example.com\nGrace,grace@example.com")
        XCTAssertEqual(table.count, 1)
        XCTAssertEqual(table.first?.header, ["name", "email"])
        XCTAssertEqual(table.first?.rows.count, 2)
        XCTAssertEqual(table.first?.rows.first, ["Ada", "ada@example.com"])
    }

    /// A copied spreadsheet selection arrives tab-separated, not comma'd.
    func testCopiedSpreadsheetRowsCountToo() {
        XCTAssertEqual(tables("name\tqty\nbolts\t40").first?.header, ["name", "qty"])
    }

    func testSemicolonsCountBecauseThatIsWhatSomeExportsUse() {
        XCTAssertEqual(tables("name;qty\nbolts;40").first?.rows.first, ["bolts", "40"])
    }

    /// The one that makes a CSV correct rather than merely displayed: a value
    /// with a comma inside it is quoted, and splitting through the quotes would
    /// shift every column after it by one.
    func testAQuotedCommaStaysInsideItsField() {
        let table = tables("name,city\n\"Smith, J.\",Bangkok\nLee,Chiang Mai")
        XCTAssertEqual(table.first?.rows.first, ["Smith, J.", "Bangkok"])
        XCTAssertEqual(table.first?.rows.last, ["Lee", "Chiang Mai"])
    }

    func testADoubledQuoteIsOneQuote() {
        XCTAssertEqual(
            DelimitedTableParser.fields(of: "\"say \"\"hi\"\"\",b", delimiter: ","),
            ["say \"hi\"", "b"]
        )
    }

    // MARK: - What must stay prose

    func testOneLineOfCommasIsASentence() {
        XCTAssertTrue(tables("get milk, bread, and eggs").isEmpty)
    }

    /// Two prose lines almost never carry an identical number of commas — but
    /// when they do, the run still has to look like data rather than words.
    func testAParagraphIsNotAGrid() {
        let text = """
        I went to the shop, and then home.
        It was raining, so I hurried.
        """
        XCTAssertTrue(prose(text).contains { $0.contains("I went to the shop") })
    }

    func testTextWithNoDelimiterAtAllIsUntouched() {
        XCTAssertEqual(prose("just a normal message\nover two lines").count, 1)
        XCTAssertTrue(tables("just a normal message\nover two lines").isEmpty)
    }

    func testRowsOfNothingAreNotData() {
        XCTAssertTrue(tables(",,\n,,").isEmpty)
    }

    /// The pipe parser goes first: a markdown separator row (`---|---`) is
    /// consistent enough to look delimited, and the two parsers fighting over
    /// one table would give the person two half-tables.
    func testAMarkdownTableIsStillAMarkdownTable() {
        let text = """
        | name | qty |
        | --- | --- |
        | bolts | 40 |
        """
        let found = tables(text)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.header, ["name", "qty"])
        XCTAssertEqual(found.first?.rows, [["bolts", "40"]])
    }

    /// Prose above and below the rows survives as prose, in order — a message
    /// is usually "here are the rows:" and then the rows.
    func testTheWordsAroundTheRowsStay() {
        let segments = DelimitedTableParser.segments(of: """
        Here are the rows:
        name,qty
        bolts,40
        That's all of them.
        """)
        guard segments.count == 3 else { return XCTFail("Got: \(segments)") }
        XCTAssertEqual(segments[0], .text("Here are the rows:"))
        if case .table = segments[1] {} else { XCTFail("Expected the rows in the middle") }
        XCTAssertEqual(segments[2], .text("That's all of them."))
    }
}

/// The two signals that separate rows from writing, pinned on their own.
extension DelimitedTableTests {
    func testASentenceEndingIsNotACell() {
        XCTAssertFalse(DelimitedTableParser.looksLikeData(["I went to the shop", "and then home."]))
        XCTAssertTrue(DelimitedTableParser.looksLikeData(["bolts", "40"]))
    }

    /// A long cell is a clause. The cost is stated where the rule lives: a
    /// column of long notes stays prose, which is the safe way round.
    func testACellIsShort() {
        XCTAssertFalse(DelimitedTableParser.looksLikeData([
            "this is a rather long run of words that reads as a clause", "x"
        ]))
    }
}
