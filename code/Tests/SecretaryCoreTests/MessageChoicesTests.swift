import XCTest
@testable import SecretaryCore

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

    func testTheMarkerIsRemovedFromWhatIsShown() {
        let parsed = MessageChoices.parse("Pick one.\n\n```choices\nOne\nTwo\n```")
        XCTAssertFalse(parsed.body.contains("```"), "Got: \(parsed.body)")
        XCTAssertFalse(parsed.body.contains("choices"), "Got: \(parsed.body)")
    }

    func testListMarkersAreStrippedFromOptions() {
        let parsed = MessageChoices.parse("```choices\n- First\n2. Second\n• Third\n```")
        XCTAssertEqual(parsed.options, ["First", "Second", "Third"])
    }

    func testAnUnclosedBlockStillYieldsItsOptions() {
        let parsed = MessageChoices.parse("Pick:\n```choices\nOne\nTwo")
        XCTAssertEqual(parsed.options, ["One", "Two"])
        XCTAssertEqual(parsed.body, "Pick:")
    }

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

    func testAnOrdinaryCodeBlockIsNotAQuestion() {
        let message = "Here you go:\n\n```swift\nlet x = 1\n```"
        let parsed = MessageChoices.parse(message)
        XCTAssertFalse(parsed.isAsking)
        XCTAssertEqual(parsed.body, message)
    }
}
