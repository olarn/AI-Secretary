import XCTest
@testable import SecretaryCore

/// Turning a marked question into options, and — more importantly — leaving
/// everything else alone.
final class MessageChoicesTests: XCTestCase {
    func testAMarkedQuestionBecomesOptions() {
        let parsed = MessageChoices.parse("""
        Does the mock API keep state?

        ```choices
        Stateless — the same fixture every time
        Stateful — a POST has to be visible to the next GET
        ```
        """)
        XCTAssertEqual(parsed.options, [
            "Stateless — the same fixture every time",
            "Stateful — a POST has to be visible to the next GET"
        ])
        XCTAssertEqual(parsed.body, "Does the mock API keep state?")
        XCTAssertTrue(parsed.isAsking)
    }

    /// The reason this is marker-based rather than read out of the prose.
    /// Both of these are real replies from testing: one lists candidate stacks,
    /// the other lists steps about to be taken. Neither is a question, and a
    /// picker over either would be wrong.
    func testOrdinaryListsAreNotQuestions() {
        for message in [
            """
            บอกสั้นๆ ได้ไหมว่าจะเอาสแตกไหน:

            - Node + Express — เบาสุด
            - Python + FastAPI — ได้ Swagger UI
            - JSON ไฟล์เดียว + json-server
            """,
            """
            ถ้ากดอนุญาตให้ อาเนียจะ:
            1. เปิด en.wikipedia.org/wiki/Thailand ในแท็บใหม่
            2. scroll ลงครึ่งหน้า
            3. scroll ต่ออีกครึ่งหน้า
            """
        ] {
            let parsed = MessageChoices.parse(message)
            XCTAssertFalse(parsed.isAsking, "Should have stayed prose")
            XCTAssertEqual(parsed.body, message, "An unmarked message must pass through untouched")
        }
    }

    /// The block must not survive into the rendered text.
    func testTheMarkerIsRemovedFromWhatIsShown() {
        let parsed = MessageChoices.parse("Pick one.\n\n```choices\nOne\nTwo\n```")
        XCTAssertFalse(parsed.body.contains("```"), "Got: \(parsed.body)")
        XCTAssertFalse(parsed.body.contains("choices"), "Got: \(parsed.body)")
    }

    /// Models reach for list markers by habit. A bullet left on the front would
    /// be sent back as part of the answer — and a message starting with a dash
    /// is exactly what broke the CLI once already.
    func testListMarkersAreStrippedFromOptions() {
        let parsed = MessageChoices.parse("```choices\n- First\n2. Second\n• Third\n```")
        XCTAssertEqual(parsed.options, ["First", "Second", "Third"])
    }

    /// A reply cut off mid-stream still offers what arrived, rather than
    /// swallowing the rest of the message.
    func testAnUnclosedBlockStillYieldsItsOptions() {
        let parsed = MessageChoices.parse("Pick:\n```choices\nOne\nTwo")
        XCTAssertEqual(parsed.options, ["One", "Two"])
        XCTAssertEqual(parsed.body, "Pick:")
    }

    /// An empty block isn't a question, and nothing may be quietly dropped from
    /// the message on the way out.
    func testAnEmptyBlockLeavesTheMessageIntact() {
        let message = "Nothing to choose.\n\n```choices\n```"
        let parsed = MessageChoices.parse(message)
        XCTAssertFalse(parsed.isAsking)
        XCTAssertEqual(parsed.body, message)
    }

    func testTooManyOptionsAreCappedRatherThanRejected() {
        let many = (1...20).map(String.init).joined(separator: "\n")
        let parsed = MessageChoices.parse("```choices\n\(many)\n```")
        XCTAssertEqual(parsed.options.count, MessageChoices.maximumOptions)
        XCTAssertEqual(parsed.options.first, "1")
    }

    /// A code block that happens to be in the reply must not be mistaken for
    /// the marker.
    func testAnOrdinaryCodeBlockIsNotAQuestion() {
        let message = "Here you go:\n\n```swift\nlet x = 1\n```"
        let parsed = MessageChoices.parse(message)
        XCTAssertFalse(parsed.isAsking)
        XCTAssertEqual(parsed.body, message)
    }
}
