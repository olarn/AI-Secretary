import XCTest
import FunctionalCore
@testable import SecretaryCore

final class EmptyTranscriptHintTests: XCTestCase {
    /// The makers the app can run a turn through, as the view passes them.
    private let makers = ["Claude Code", "OpenCode"]

    /// Asserted whole, not by `contains`. The defect this file exists for was
    /// thirteen spaces in the middle of a sentence — invisible to any assertion
    /// that only checks a fragment is in there somewhere.
    func testTheReadyHintBreaksOnceBetweenItsTwoSentences() {
        XCTAssertEqual(
            emptyTranscriptHint(.ready(version: .some("2.1.233")), makers: makers),
            """
            Ready — I'll work through the AI tool you've set up (2.1.233).
            Add a project, then just tell me what you need in your own words.
            """
        )
    }

    /// One break, never two: a blank line between two short sentences reads as
    /// a gap rather than as structure, which is what it looked like on screen.
    func testNoStateCarriesABlankLine() {
        let states: [BackendReadiness] = [
            .looking,
            .notInstalled,
            .ready(version: .none()),
            .ready(version: .some("2.1.233"))
        ]
        for state in states {
            XCTAssertFalse(
                emptyTranscriptHint(state, makers: makers).contains("\n\n"),
                "\(state) has a blank line in it"
            )
        }
    }

    /// The version rides in brackets when there is one and takes its space with
    /// it when there isn't, so the full stop never arrives after a gap.
    func testAnUnreportedVersionLeavesNoGap() {
        XCTAssertEqual(
            emptyTranscriptHint(.ready(version: .none()), makers: makers),
            """
            Ready — I'll work through the AI tool you've set up.
            Add a project, then just tell me what you need in your own words.
            """
        )
    }

    func testLookingAndNotInstalledSayDifferentThings() {
        XCTAssertEqual(emptyTranscriptHint(.looking, makers: makers), "Checking for your AI tool…")
        XCTAssertEqual(
            emptyTranscriptHint(.notInstalled, makers: makers),
            "Install Claude Code or OpenCode and sign in, and I'll be able to work for you."
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
                emptyTranscriptHint(state, makers: makers).contains("  "),
                "\(state) has a run of spaces in it"
            )
        }
    }
}

/// The sentence has to stay English however many makers there are, including
/// none — an empty list would otherwise print "Install  and sign in", the same
/// class of invisible whitespace defect this file was written for.
final class MakerListTests: XCTestCase {
    func testNoMakersStillReadsAsASentence() {
        XCTAssertEqual(makerList([]), "an AI coding tool")
    }

    func testOneMakerIsNamedAlone() {
        XCTAssertEqual(makerList(["Claude Code"]), "Claude Code")
    }

    func testTwoMakersAreJoinedWithOr() {
        XCTAssertEqual(makerList(["Claude Code", "OpenCode"]), "Claude Code or OpenCode")
    }

    /// Three is the case a two-way join gets wrong, and the app is one vendor
    /// away from it.
    func testThreeMakersCommaUntilTheLast() {
        XCTAssertEqual(makerList(["A", "B", "C"]), "A, B or C")
    }
}
