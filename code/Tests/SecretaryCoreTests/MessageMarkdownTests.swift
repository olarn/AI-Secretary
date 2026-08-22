import XCTest
@testable import SecretaryCore

final class MessageMarkdownTests: XCTestCase {

    private func links(in text: String) -> [URL] {
        MessageMarkdown.attributed(text).runs.compactMap(\.link)
    }

    private func plainText(of text: String) -> String {
        String(MessageMarkdown.attributed(text).characters)
    }

    func testABareURLBecomesALink() {
        XCTAssertEqual(
            links(in: "See https://example.com/docs for the details."),
            [URL(string: "https://example.com/docs")!]
        )
    }

    func testTheSurroundingTextIsUntouched() {
        let source = "See https://example.com for details."
        XCTAssertEqual(plainText(of: source), source)
    }

    func testSeveralURLsInOneMessageAreAllLinked() {
        XCTAssertEqual(links(in: "a https://one.example b https://two.example").count, 2)
    }

    func testAURLInThaiTextIsLinked() {
        XCTAssertEqual(
            links(in: "ดูรายละเอียดที่ https://example.com/ราคา นะครับ").first?.host,
            "example.com"
        )
    }

    func testAMarkdownLinkKeepsItsLabelAndTarget() {
        let attributed = MessageMarkdown.attributed("Read [the docs](https://example.com/docs).")
        XCTAssertEqual(String(attributed.characters), "Read the docs.")
        XCTAssertEqual(attributed.runs.compactMap(\.link), [URL(string: "https://example.com/docs")!])
    }

    func testALabelThatLooksLikeAURLKeepsTheMarkdownTarget() {
        let links = links(in: "[https://decoy.example](https://real.example/page)")
        XCTAssertEqual(links, [URL(string: "https://real.example/page")!])
    }

    func testUnsafeSchemesAreNotClickable() {
        for source in [
            "[open me](file:///etc/passwd)",
            "[run me](javascript:alert(1))",
            "[install](itms-apps://example.com)"
        ] {
            XCTAssertTrue(links(in: source).isEmpty, "Should not be a link: \(source)")
        }
    }

    func testTheLabelOfAStrippedLinkIsStillShown() {
        XCTAssertEqual(plainText(of: "[open me](file:///etc/passwd)"), "open me")
    }

    func testMailtoIsAllowed() {
        XCTAssertEqual(
            links(in: "[write](mailto:someone@example.com)").first?.scheme,
            "mailto"
        )
    }

    func testTextWithoutLinksIsUnchanged() {
        let source = "No links here — just a sentence with 2 * 3 in it."
        XCTAssertEqual(plainText(of: source), source)
        XCTAssertTrue(links(in: source).isEmpty)
    }

    func testNewlinesSurvive() {
        XCTAssertEqual(plainText(of: "line one\nline two"), "line one\nline two")
    }

    func testInlineMarkdownIsApplied() {
        XCTAssertEqual(plainText(of: "a **bold** word"), "a bold word")
    }
}
