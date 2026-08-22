import XCTest
@testable import SecretaryCore

final class BlockedBlockTests: XCTestCase {
    func testAMarkedBlockRecordsWhatWasMissing() {
        let parsed = BlockedBlock.parse("""
        The folder is empty — I can't see any ratebook here.

        ```blocked
        where the ratebook data lives, or a project whose MCP serves it
        ```
        """)
        XCTAssertEqual(parsed.missing, "where the ratebook data lives, or a project whose MCP serves it")
        XCTAssertEqual(parsed.body, "The folder is empty — I can't see any ratebook here.")
    }

    func testTheMarkerIsStrippedFromWhatIsShown() {
        let parsed = BlockedBlock.parse("Nope.\n```blocked\na path\n```")
        XCTAssertFalse(parsed.body.contains("```"), parsed.body)
        XCTAssertFalse(parsed.body.contains("a path"), parsed.body)
    }

    func testProseIsNotTreatedAsBlocked() {
        for message in [
            "I couldn't find a ratebook in that folder, but here's what is there.",
            "That file doesn't exist yet.",
            "```swift\nlet x = 1\n```"
        ] {
            let parsed = BlockedBlock.parse(message)
            XCTAssertNil(parsed.missing, "Should not be blocked: \(message)")
            XCTAssertEqual(parsed.body, message)
        }
    }

    func testAnEmptyBlockIsIgnoredAndTheMessageLeftWhole() {
        let message = "hm\n```blocked\n```"
        let parsed = BlockedBlock.parse(message)
        XCTAssertNil(parsed.missing)
        XCTAssertEqual(parsed.body, message)
    }

    func testTheReminderNamesBothTheRequestAndTheGap() {
        let outstanding = OutstandingRequest(
            request: "ratebook for Vios and City, 2022, and pin it",
            missing: "a project whose MCP serves ratebook data"
        )
        XCTAssertTrue(outstanding.reminder.contains("ratebook for Vios and City, 2022, and pin it"))
        XCTAssertTrue(outstanding.reminder.contains("a project whose MCP serves ratebook data"))
        XCTAssertTrue(outstanding.reminder.lowercased().contains("pin"),
                      "The pinning half of a request is the part most often dropped")
    }
}
