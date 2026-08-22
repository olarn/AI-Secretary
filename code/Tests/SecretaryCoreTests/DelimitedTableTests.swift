import FunctionalCore
import XCTest
@testable import SecretaryCore

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

    func testCopiedSpreadsheetRowsCountToo() {
        XCTAssertEqual(tables("name\tqty\nbolts\t40").first?.header, ["name", "qty"])
    }

    func testSemicolonsCountBecauseThatIsWhatSomeExportsUse() {
        XCTAssertEqual(tables("name;qty\nbolts;40").first?.rows.first, ["bolts", "40"])
    }

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

    func testOneLineOfCommasIsASentence() {
        XCTAssertTrue(tables("get milk, bread, and eggs").isEmpty)
    }

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

extension DelimitedTableTests {
    func testASentenceEndingIsNotACell() {
        XCTAssertFalse(DelimitedTableParser.looksLikeData(["I went to the shop", "and then home."]))
        XCTAssertTrue(DelimitedTableParser.looksLikeData(["bolts", "40"]))
    }

    func testACellIsShort() {
        XCTAssertFalse(DelimitedTableParser.looksLikeData([
            "this is a rather long run of words that reads as a clause", "x"
        ]))
    }
}

extension DelimitedTableTests {
    func testAThousandsSeparatorIsNotAColumnBreak() {
        let text = """
        sample.pdf: Invoice 42 for Olarn — total 1,250 THB
        note.txt: Invoice 42 for Olarn — total 1,250 THB
        """
        XCTAssertTrue(
            DelimitedTableParser.segments(of: text).allSatisfy { if case .text = $0 { return true } else { return false } },
            "Got: \(DelimitedTableParser.segments(of: text))"
        )
        XCTAssertEqual(
            DelimitedTableParser.fields(of: "total 1,250 THB", delimiter: ","),
            ["total 1,250 THB"]
        )
    }

    func testAColumnOfMoneyStillSplits() {
        XCTAssertEqual(
            tables("item,amount\nlunch,1250\ntaxi,300").first?.rows,
            [["lunch", "1250"], ["taxi", "300"]]
        )
        XCTAssertEqual(
            DelimitedTableParser.fields(of: "\"1,250\",THB", delimiter: ","),
            ["1,250", "THB"]
        )
    }
}
