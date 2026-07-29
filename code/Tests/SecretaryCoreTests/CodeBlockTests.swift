import XCTest
@testable import SecretaryCore

/// Code and JSON in a reply must survive to the screen unchanged.
///
/// The inline markdown renderer is deliberately given
/// `.inlineOnlyPreservingWhitespace` so a stray character can't restructure a
/// message — but that also swallows a fence and reflows what is inside it. A
/// JSON sample reached the chat as `json { "iso": … }` on a single line. So the
/// block has to be pulled out before the renderer ever sees it.
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

    /// The prose around it stays prose, and the fence itself never reaches the
    /// text renderer.
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

    /// Indentation and blank lines are the content of a code block, not noise.
    func testTheShapeOfTheCodeIsPreserved() {
        let block = firstCode("```\nfunc a() {\n    if b {\n        c()\n    }\n}\n```")
        XCTAssertEqual(block?.code, "func a() {\n    if b {\n        c()\n    }\n}")
        XCTAssertNil(block?.language)
    }

    /// A block may contain pipes and dashes. Looking for tables inside one
    /// would tear it apart, so code is found first.
    func testAPipeInsideCodeIsNotATable() {
        let block = firstCode("```sh\ncat a.txt | grep -v x\n```")
        XCTAssertEqual(block?.code, "cat a.txt | grep -v x")
        XCTAssertFalse(
            MarkdownTableParser.segments(of: "```sh\na | b\n--- | ---\nc | d\n```")
                .contains { if case .table = $0 { return true } else { return false } }
        )
    }

    /// Replies stream in, so the closing fence may not have arrived yet.
    func testAnUnclosedFenceStillRendersAsCode() {
        XCTAssertEqual(firstCode("```python\nprint(1)")?.code, "print(1)")
    }

    /// The app's own question marker is handled elsewhere and must never be
    /// drawn as a code block.
    func testTheChoicesMarkerIsNotCode() {
        XCTAssertNil(firstCode("Pick one.\n\n```choices\nFirst\nSecond\n```"))
    }

    /// An empty fence is punctuation, not code, and must not leave an empty box
    /// in the conversation.
    func testAnEmptyFenceIsNotCode() {
        XCTAssertNil(firstCode("nothing here\n\n```\n```"))
    }

    /// Tables must keep working alongside code in the same message.
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

    /// A message with no fences is untouched — the common case.
    func testAnOrdinaryMessageHasNoCode() {
        XCTAssertNil(firstCode("just a sentence with `inline code` in it"))
    }
}
