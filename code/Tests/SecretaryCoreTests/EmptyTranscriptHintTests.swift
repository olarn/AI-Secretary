import XCTest
import FunctionalCore
@testable import SecretaryCore

final class EmptyTranscriptHintTests: XCTestCase {
    /// Asserted whole, not by `contains`. The defect this file exists for was
    /// thirteen spaces in the middle of a sentence — invisible to any assertion
    /// that only checks a fragment is in there somewhere.
    func testTheReadyHintReadsAsTwoParagraphs() {
        XCTAssertEqual(
            emptyTranscriptHint(.ready(version: .some("2.1.233"))),
            """
            Ready — I'll work through your own Claude Code (2.1.233).

            Add a project, then just tell me what you need in your own words.
            """
        )
    }

    /// The version rides in brackets when there is one and takes its space with
    /// it when there isn't, so the full stop never arrives after a gap.
    func testAnUnreportedVersionLeavesNoGap() {
        XCTAssertEqual(
            emptyTranscriptHint(.ready(version: .none())),
            """
            Ready — I'll work through your own Claude Code.

            Add a project, then just tell me what you need in your own words.
            """
        )
    }

    func testLookingAndNotInstalledSayDifferentThings() {
        XCTAssertEqual(emptyTranscriptHint(.looking), "Checking for Claude Code…")
        XCTAssertEqual(
            emptyTranscriptHint(.notInstalled),
            "Install Claude Code and sign in, and I'll be able to work for you."
        )
    }

    /// No run of spaces anywhere, in any state. The one that shipped came from
    /// a collapsed line break, and nothing about that is specific to the string
    /// it happened to land in.
    func testNoStateCarriesADoubleSpace() {
        let states: [BackendReadiness] = [
            .looking,
            .notInstalled,
            .ready(version: .none()),
            .ready(version: .some("2.1.233"))
        ]
        for state in states {
            XCTAssertFalse(
                emptyTranscriptHint(state).contains("  "),
                "\(state) has a run of spaces in it"
            )
        }
    }
}
