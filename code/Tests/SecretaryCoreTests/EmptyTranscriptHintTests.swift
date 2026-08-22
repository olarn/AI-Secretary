import XCTest
import FunctionalCore
@testable import SecretaryCore

final class EmptyTranscriptHintTests: XCTestCase {
    private let makers = ["Claude Code", "OpenCode"]

    func testTheReadyHintBreaksOnceBetweenItsTwoSentences() {
        XCTAssertEqual(
            emptyTranscriptHint(.ready(version: .some("2.1.233")), makers: makers),
            """
            Ready — I'll work through the AI tool you've set up (2.1.233).
            Add a project, then just tell me what you need in your own words.
            """
        )
    }

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

    func testThreeMakersCommaUntilTheLast() {
        XCTAssertEqual(makerList(["A", "B", "C"]), "A, B or C")
    }
}
