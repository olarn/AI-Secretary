import XCTest
@testable import SecretaryCore

/// Reading the steps back out of a reply.
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

    /// Steps are the natural thing to number, and the model does it about half
    /// the time however it is asked. A step called "1. Pull" would be sent to
    /// the next turn with the numbering baked in twice.
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

    /// A digit inside a step is not a bullet. "3 files" must survive.
    func testTextThatMerelyStartsWithProseIsLeftAlone() {
        let parsed = PlanBlock.parse("""
        ```plan
        Check that 3 files exist
        ```
        """)
        XCTAssertEqual(parsed.steps, ["Check that 3 files exist"])
    }

    /// An empty block asks for nothing, so it must not produce a plan with no
    /// steps that the card would then offer to run.
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

    /// Nothing runs after a halt, however many times the caller advances — the
    /// stop has to be the last word or a queued turn could restart it.
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

    /// One character is a different instruction.
    func testADifferentTextGivesADifferentFingerprint() {
        XCTAssertNotEqual(
            InstructionFingerprint.of("deploy to staging"),
            InstructionFingerprint.of("deploy to production")
        )
    }
}

final class InstructionMemoryTests: XCTestCase {
    /// A file never run here has nothing to have changed from. Saying "the
    /// steps changed" on a first run would train the person to click past it.
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

    /// Files are remembered separately — editing one must not make another
    /// look edited.
    func testFilesAreRememberedApart() {
        let memory = InstructionMemory()
            .recording(path: "deploy.md", fingerprint: "abc")
            .recording(path: "release.md", fingerprint: "xyz")
        XCTAssertFalse(memory.hasChanged(path: "release.md", fingerprint: "xyz"))
        XCTAssertTrue(memory.hasChanged(path: "deploy.md", fingerprint: "zzz"))
    }
}
