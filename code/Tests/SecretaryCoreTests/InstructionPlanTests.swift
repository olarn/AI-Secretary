import XCTest
@testable import SecretaryCore

final class PlanBlockTests: XCTestCase {
    func testAMessageWithNoBlockComesBackUntouched() {
        let text = "Here's what I'd do: pull, then test."
        let parsed = PlanBlock.parse(text)
        XCTAssertEqual(parsed.body, text)
        XCTAssertTrue(parsed.steps.isEmpty)
    }

    func testTheBlockIsTakenOutOfTheBody() {
        let parsed = PlanBlock.parse("""
        This file sets up the release.

        ```plan
        Pull the latest changes
        Run the test suite
        ```
        """)
        XCTAssertEqual(parsed.steps, ["Pull the latest changes", "Run the test suite"])
        XCTAssertEqual(parsed.body, "This file sets up the release.")
        XCTAssertFalse(parsed.body.contains("```"), "The raw block must never reach the eye")
    }

    func testNumberingAndBulletsAreStripped() {
        let parsed = PlanBlock.parse("""
        ```plan
        1. Pull the latest changes
        2) Run the tests
        - Tag the release
        • Announce it
        ```
        """)
        XCTAssertEqual(
            parsed.steps,
            ["Pull the latest changes", "Run the tests", "Tag the release", "Announce it"]
        )
    }

    func testTextThatMerelyStartsWithProseIsLeftAlone() {
        let parsed = PlanBlock.parse("""
        ```plan
        Check that 3 files exist
        ```
        """)
        XCTAssertEqual(parsed.steps, ["Check that 3 files exist"])
    }

    func testAnEmptyBlockYieldsNoPlanAndKeepsTheMessageWhole() {
        let text = "```plan\n\n```"
        let parsed = PlanBlock.parse(text)
        XCTAssertTrue(parsed.steps.isEmpty)
        XCTAssertEqual(parsed.body, text)
    }
}

final class InstructionRunTests: XCTestCase {
    private func run(steps: [String]) -> InstructionRun {
        InstructionRun(plan: InstructionPlan(
            relativePath: "deploy.md",
            fingerprint: "abc123",
            steps: steps
        ))
    }

    func testItStartsOnTheFirstStep() {
        let started = run(steps: ["one", "two"])
        XCTAssertEqual(started.currentStep.toOptional(), "one")
        XCTAssertEqual(started.stepNumber, 1)
        XCTAssertEqual(started.totalSteps, 2)
        XCTAssertTrue(started.isRunning)
    }

    func testTheLastStepFinishesTheRun() {
        let finished = run(steps: ["one", "two"]).advancing().advancing()
        XCTAssertEqual(finished.status, .finished)
        XCTAssertFalse(finished.isRunning)
        XCTAssertEqual(finished.currentStep, .none(), "A finished run has nothing to send")
    }

    func testAHaltedRunStaysHalted() {
        let halted = run(steps: ["one", "two"]).halting(reason: "the file changed").advancing()
        XCTAssertEqual(halted.status, .halted(reason: "the file changed"))
        XCTAssertEqual(halted.currentStep, .none())
    }

    func testItSaysWhereItGotTo() {
        XCTAssertEqual(
            run(steps: ["one", "two", "three"]).advancing().progressDescription,
            "Step 2 of 3 of deploy.md"
        )
        XCTAssertEqual(
            run(steps: ["one"]).halting(reason: "you stopped it").progressDescription,
            "Stopped at step 1 of 1 of deploy.md — you stopped it"
        )
    }
}

final class InstructionFingerprintTests: XCTestCase {
    func testTheSameTextGivesTheSameFingerprint() {
        XCTAssertEqual(InstructionFingerprint.of("do the thing"), InstructionFingerprint.of("do the thing"))
    }

    func testADifferentTextGivesADifferentFingerprint() {
        XCTAssertNotEqual(
            InstructionFingerprint.of("deploy to staging"),
            InstructionFingerprint.of("deploy to production")
        )
    }
}

final class InstructionMemoryTests: XCTestCase {
    func testAFirstRunHasNotChanged() {
        let memory = InstructionMemory()
        XCTAssertFalse(memory.hasChanged(path: "deploy.md", fingerprint: "abc"))
    }

    func testRunningTheSameFileUnchangedSaysNothing() {
        let memory = InstructionMemory().recording(path: "deploy.md", fingerprint: "abc")
        XCTAssertFalse(memory.hasChanged(path: "deploy.md", fingerprint: "abc"))
    }

    func testAnEditedFileIsReportedAsChanged() {
        let memory = InstructionMemory().recording(path: "deploy.md", fingerprint: "abc")
        XCTAssertTrue(memory.hasChanged(path: "deploy.md", fingerprint: "def"))
    }

    func testFilesAreRememberedApart() {
        let memory = InstructionMemory()
            .recording(path: "deploy.md", fingerprint: "abc")
            .recording(path: "release.md", fingerprint: "xyz")
        XCTAssertFalse(memory.hasChanged(path: "release.md", fingerprint: "xyz"))
        XCTAssertTrue(memory.hasChanged(path: "deploy.md", fingerprint: "zzz"))
    }
}
