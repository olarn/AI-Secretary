import XCTest
@testable import SecretaryCore

final class LoopBlockTests: XCTestCase {
    func testAMarkedBlockAsksForALoop() {
        let parsed = LoopBlock.parse("""
        ได้เลย จะคอยบอกให้

        ```loop
        every: 10m
        บอกว่าถึงหัวข้อไหนแล้ว
        ```
        """)
        XCTAssertEqual(parsed.request, .start(interval: 600, note: "บอกว่าถึงหัวข้อไหนแล้ว"))
        XCTAssertEqual(parsed.body, "ได้เลย จะคอยบอกให้")
    }

    func testTheEveryLabelIsOptional() {
        XCTAssertEqual(
            LoopBlock.parse("ok\n```loop\n15m\nreport\n```").request,
            .start(interval: 900, note: "report")
        )
    }

    func testWillingProseDoesNotStartATimer() {
        for message in [
            "จะคอยดูให้นะ ถ้ามีอะไรเปลี่ยนจะบอก",
            "I'll keep track of where we are and let you know every 10 minutes.",
            "ตอนนี้ 10:46 — กำลังอยู่ที่ Break (10:45 – 11:00)"
        ] {
            let parsed = LoopBlock.parse(message)
            XCTAssertNil(parsed.request, "Should not have started a loop: \(message)")
            XCTAssertEqual(parsed.body, message, "An unmarked message must pass through untouched")
        }
    }

    func testTheBlockNeverSurvivesIntoWhatIsShown() {
        let parsed = LoopBlock.parse("Tracking.\n\n```loop\nevery: 10m\nwhere are we\n```")
        XCTAssertFalse(parsed.body.contains("```"), "Got: \(parsed.body)")
        XCTAssertFalse(parsed.body.contains("10m"), "Got: \(parsed.body)")
    }

    func testStopCanBeAskedForInTheBlock() {
        XCTAssertEqual(LoopBlock.parse("done\n```loop\nstop\n```").request, .stop)
        XCTAssertEqual(LoopBlock.parse("เสร็จแล้ว\n```loop\nหยุด\n```").request, .stop)
    }

    func testAnOutOfBoundsIntervalStartsNothing() {
        for interval in ["5s", "9h", "soon"] {
            let message = "ok\n```loop\nevery: \(interval)\nreport\n```"
            let parsed = LoopBlock.parse(message)
            XCTAssertNil(parsed.request, "Should have refused “\(interval)”")
            XCTAssertEqual(parsed.body, message)
        }
    }

    func testAnEmptyBlockLeavesTheMessageIntact() {
        let message = "nothing\n\n```loop\n```"
        let parsed = LoopBlock.parse(message)
        XCTAssertNil(parsed.request)
        XCTAssertEqual(parsed.body, message)
    }

    func testABlockWithNoNoteFallsBackToTheDefault() {
        guard case .start(_, let note)? = LoopBlock.parse("ok\n```loop\n10m\n```").request else {
            return XCTFail("Expected a start request")
        }
        XCTAssertTrue(note.isEmpty)
        XCTAssertEqual(
            LoopSchedule.starting(interval: 600, note: note, now: Date()).note,
            LoopSchedule.defaultNote
        )
    }

    func testOtherFencedBlocksAreLeftAlone() {
        for message in [
            "Here:\n\n```swift\nlet x = 1\n```",
            "Pick one.\n\n```choices\nFirst\nSecond\n```"
        ] {
            let parsed = LoopBlock.parse(message)
            XCTAssertNil(parsed.request)
            XCTAssertEqual(parsed.body, message)
        }
    }
}
