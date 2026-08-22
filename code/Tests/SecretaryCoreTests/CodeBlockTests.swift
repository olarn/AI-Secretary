import XCTest
@testable import SecretaryCore

final class CodeBlockTests: XCTestCase {
    private func firstCode(_ text: String) -> CodeBlock? {
        for case .code(let block) in MarkdownTableParser.segments(of: text) { return block }
        return nil
    }

    func testAFencedBlockBecomesCode() {
        let block = firstCode("""
        Here's the shape:

        ```json
        { "iso": "2026-07-29T11:10:00.000Z", "timezone": "Asia/Bangkok" }
        ```
        """)
        XCTAssertEqual(block?.language, "json")
        XCTAssertEqual(
            block?.code,
            #"{ "iso": "2026-07-29T11:10:00.000Z", "timezone": "Asia/Bangkok" }"#
        )
    }

    func testTheProseAroundItIsKept() {
        let segments = MarkdownTableParser.segments(of: "Before\n\n```swift\nlet x = 1\n```\n\nAfter")
        guard case .text(let before) = segments.first else { return XCTFail("Expected prose first") }
        guard case .text(let after) = segments.last else { return XCTFail("Expected prose last") }
        XCTAssertEqual(before, "Before")
        XCTAssertEqual(after, "After")
        XCTAssertEqual(segments.count, 3)
        for segment in segments {
            if case .text(let body) = segment {
                XCTAssertFalse(body.contains("```"), "A fence leaked into prose: \(body)")
            }
        }
    }

    func testTheShapeOfTheCodeIsPreserved() {
        let block = firstCode("```\nfunc a() {\n    if b {\n        c()\n    }\n}\n```")
        XCTAssertEqual(block?.code, "func a() {\n    if b {\n        c()\n    }\n}")
        XCTAssertNil(block?.language)
    }

    func testAPipeInsideCodeIsNotATable() {
        let block = firstCode("```sh\ncat a.txt | grep -v x\n```")
        XCTAssertEqual(block?.code, "cat a.txt | grep -v x")
        XCTAssertFalse(
            MarkdownTableParser.segments(of: "```sh\na | b\n--- | ---\nc | d\n```")
                .contains { if case .table = $0 { return true } else { return false } }
        )
    }

    func testAnUnclosedFenceStillRendersAsCode() {
        XCTAssertEqual(firstCode("```python\nprint(1)")?.code, "print(1)")
    }

    func testTheChoicesMarkerIsNotCode() {
        XCTAssertNil(firstCode("Pick one.\n\n```choices\nFirst\nSecond\n```"))
    }

    func testAnEmptyFenceIsNotCode() {
        XCTAssertNil(firstCode("nothing here\n\n```\n```"))
    }

    func testATableAndACodeBlockCanCoexist() {
        let segments = MarkdownTableParser.segments(of: """
        | a | b |
        | --- | --- |
        | 1 | 2 |

        ```json
        {"ok": true}
        ```
        """)
        XCTAssertTrue(segments.contains { if case .table = $0 { return true } else { return false } })
        XCTAssertTrue(segments.contains { if case .code = $0 { return true } else { return false } })
    }

    func testAnOrdinaryMessageHasNoCode() {
        XCTAssertNil(firstCode("just a sentence with `inline code` in it"))
    }
}
