import XCTest
@testable import LLMProvider

final class ClaudeCodeDetectorTests: XCTestCase {
    private func countingLocator(_ searches: SearchCount) -> ClaudeCodeLocator {
        ClaudeCodeLocator(
            isExecutable: { $0.hasSuffix("/.local/bin/claude") },
            probe: { _ in
                searches.note()
                return "2.1.228 (Claude Code)"
            }
        )
    }

    final class SearchCount: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func note() { lock.withLock { value += 1 } }
        var searches: Int { lock.withLock { value } }
    }

    func testTheSearchRunsOnceHoweverManyBackendsAskForIt() {
        let count = SearchCount()
        let detector = ClaudeCodeDetector(locator: countingLocator(count))

        let miku = ChatBackend(detector: detector)
        let anya = ChatBackend(detector: detector)
        miku.resolveOffTheMainThread()
        anya.resolveOffTheMainThread()
        detector.resolveOffTheMainThread()

        XCTAssertEqual(count.searches, 1)
    }

    func testEveryBackendGetsItsOwnHandleOnClaudeCode() {
        let detector = ClaudeCodeDetector(locator: countingLocator(SearchCount()))
        let miku = ChatBackend(detector: detector)
        let anya = ChatBackend(detector: detector)
        miku.resolveOffTheMainThread()
        anya.resolveOffTheMainThread()

        miku.adoptSession("miku-session")

        XCTAssertEqual(miku.currentSessionID, "miku-session")
        XCTAssertNil(anya.currentSessionID)
    }

    func testABackendBuiltAfterDetectionStillGetsAProvider() {
        let detector = ClaudeCodeDetector(locator: countingLocator(SearchCount()))
        detector.resolveOffTheMainThread()

        let late = ChatBackend(detector: detector)

        XCTAssertTrue(late.hasWorkspaceTools)
        XCTAssertNotNil(late.installation)
    }

    func testAChoiceMadeBeforeDetectionIsCarriedIntoTheProvider() {
        let detector = ClaudeCodeDetector(locator: countingLocator(SearchCount()))
        let early = ChatBackend(detector: detector)

        early.adoptSession("chosen-before-launch")
        XCTAssertEqual(early.currentSessionID, "chosen-before-launch")

        early.resolveOffTheMainThread()
        XCTAssertEqual(early.currentSessionID, "chosen-before-launch")
    }

    func testEveryWatcherHearsTheResult() {
        let detector = ClaudeCodeDetector(locator: countingLocator(SearchCount()))
        let heard = Heard()
        detector.observe { _ in heard.bump() }
        detector.observe { _ in heard.bump() }

        detector.resolveOffTheMainThread()

        XCTAssertEqual(heard.count, 2)
    }

    func testAWatcherArrivingAfterTheAnswerIsToldImmediately() {
        let detector = ClaudeCodeDetector(locator: countingLocator(SearchCount()))
        detector.resolveOffTheMainThread()

        let heard = Heard()
        detector.observe { _ in heard.bump() }

        XCTAssertEqual(heard.count, 1)
    }

    final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }
}
