import XCTest
@testable import LLMProvider

/// The promise the detector exists to keep: the machine is searched once
/// however many characters are on the desktop, and each of them still gets her
/// own handle on Claude Code.
///
/// Worth pinning because the cost is invisible in use. A second search does not
/// fail — it launches a second login shell and quietly takes seconds, which
/// looks like the app being slow to wake up rather than like a bug.
final class ClaudeCodeDetectorTests: XCTestCase {
    /// Counts how many times the machine was actually searched.
    ///
    /// Counted on the version probe rather than on the executable test: the
    /// locator stops at the first path that exists, so how many paths it tries
    /// depends on where Claude Code happens to be, while it reads the version
    /// exactly once per completed search.
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
        miku.resolve()
        anya.resolve()
        detector.resolve()

        XCTAssertEqual(count.searches, 1)
    }

    func testEveryBackendGetsItsOwnHandleOnClaudeCode() {
        let detector = ClaudeCodeDetector(locator: countingLocator(SearchCount()))
        let miku = ChatBackend(detector: detector)
        let anya = ChatBackend(detector: detector)
        miku.resolve()
        anya.resolve()

        // A session adopted by one character must not turn up in the other's.
        // Sharing one provider is exactly the failure this split exists to
        // prevent: two conversations answering into the same thread.
        miku.adoptSession("miku-session")

        XCTAssertEqual(miku.currentSessionID, "miku-session")
        XCTAssertNil(anya.currentSessionID)
    }

    /// The ordinary case for a character created after launch: detection is
    /// long finished, so there is no event left to wait for.
    func testABackendBuiltAfterDetectionStillGetsAProvider() {
        let detector = ClaudeCodeDetector(locator: countingLocator(SearchCount()))
        detector.resolve()

        let late = ChatBackend(detector: detector)

        XCTAssertTrue(late.hasWorkspaceTools)
        XCTAssertNotNil(late.installation)
    }

    /// What a character chose before there was anything to tell has to survive
    /// until there is. Two characters can differ here, which is why it is kept
    /// per backend rather than on the detector.
    func testAChoiceMadeBeforeDetectionIsCarriedIntoTheProvider() {
        let detector = ClaudeCodeDetector(locator: countingLocator(SearchCount()))
        let early = ChatBackend(detector: detector)

        early.adoptSession("chosen-before-launch")
        XCTAssertEqual(early.currentSessionID, "chosen-before-launch")

        early.resolve()
        XCTAssertEqual(early.currentSessionID, "chosen-before-launch")
    }

    func testEveryWatcherHearsTheResult() {
        let detector = ClaudeCodeDetector(locator: countingLocator(SearchCount()))
        let heard = Heard()
        detector.observe { _ in heard.bump() }
        detector.observe { _ in heard.bump() }

        detector.resolve()

        XCTAssertEqual(heard.count, 2)
    }

    /// The app installs its watcher on the detector at launch and a character's
    /// backend installs one per character; a single-observer slot would have
    /// meant the last one silently replacing the others.
    func testAWatcherArrivingAfterTheAnswerIsToldImmediately() {
        let detector = ClaudeCodeDetector(locator: countingLocator(SearchCount()))
        detector.resolve()

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
