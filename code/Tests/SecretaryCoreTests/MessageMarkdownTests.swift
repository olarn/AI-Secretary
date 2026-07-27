import XCTest
@testable import SecretaryCore

final class MessageMarkdownTests: XCTestCase {

    private func links(in text: String) -> [URL] {
        MessageMarkdown.attributed(text).runs.compactMap(\.link)
    }

    private func plainText(of text: String) -> String {
        String(MessageMarkdown.attributed(text).characters)
    }

    // MARK: - Bare URLs

    /// The common case: the model just writes the address out.
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

    /// Thai text has no spaces around punctuation in places; the URL must still
    /// come out whole.
    func testAURLInThaiTextIsLinked() {
        XCTAssertEqual(
            links(in: "ดูรายละเอียดที่ https://example.com/ราคา นะครับ").first?.host,
            "example.com"
        )
    }

    // MARK: - Markdown links

    func testAMarkdownLinkKeepsItsLabelAndTarget() {
        let attributed = MessageMarkdown.attributed("Read [the docs](https://example.com/docs).")
        XCTAssertEqual(String(attributed.characters), "Read the docs.")
        XCTAssertEqual(attributed.runs.compactMap(\.link), [URL(string: "https://example.com/docs")!])
    }

    /// The detector must not re-point a link at something inside its own label.
    func testALabelThatLooksLikeAURLKeepsTheMarkdownTarget() {
        let links = links(in: "[https://decoy.example](https://real.example/page)")
        XCTAssertEqual(links, [URL(string: "https://real.example/page")!])
    }

    // MARK: - Untrusted input

    /// Replies quote pages and tool output, so a link can be anything. Only
    /// schemes that are safe to hand to the browser are clickable.
    func testUnsafeSchemesAreNotClickable() {
        for source in [
            "[open me](file:///etc/passwd)",
            "[run me](javascript:alert(1))",
            "[install](itms-apps://example.com)"
        ] {
            XCTAssertTrue(links(in: source).isEmpty, "Should not be a link: \(source)")
        }
    }

    /// …but the text itself is still readable, not swallowed.
    func testTheLabelOfAStrippedLinkIsStillShown() {
        XCTAssertEqual(plainText(of: "[open me](file:///etc/passwd)"), "open me")
    }

    func testMailtoIsAllowed() {
        XCTAssertEqual(
            links(in: "[write](mailto:someone@example.com)").first?.scheme,
            "mailto"
        )
    }

    // MARK: - Plain text

    func testTextWithoutLinksIsUnchanged() {
        let source = "No links here — just a sentence with 2 * 3 in it."
        XCTAssertEqual(plainText(of: source), source)
        XCTAssertTrue(links(in: source).isEmpty)
    }

    /// Replies are multi-line and the layout has to survive the round trip.
    func testNewlinesSurvive() {
        XCTAssertEqual(plainText(of: "line one\nline two"), "line one\nline two")
    }

    func testInlineMarkdownIsApplied() {
        XCTAssertEqual(plainText(of: "a **bold** word"), "a bold word")
    }
}
