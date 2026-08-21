import XCTest
import FunctionalCore
@testable import LLMProvider

/// When it is worth spending two minutes of somebody's laptop up front.
///
/// The numbers this exists for, measured on 2026-08-21 against opencode 1.18.15
/// and a local 27B: prefilling its 13,127-token prompt cold costs ~116s, and
/// 0.3s once the model has it cached. Keeping a *process* warm would have saved
/// 0.3s of that, which is why this warms the model's cache instead.
final class VendorWarmUpTests: XCTestCase {
    private let target = WarmUpTarget(
        vendorID: "opencode",
        modelID: "ollama/qwen3.8:27b-mlx",
        directory: "/Users/me/project"
    )

    func testAMakerWithNothingToWarmIsNeverWarmed() {
        // Claude Code's prompt is cached on Anthropic's side and its process is
        // already kept warm, so there is nothing here to buy.
        XCTAssertFalse(
            shouldWarmUp(target, alreadyWarmed: [], vendorWarmsUp: false, turnInFlight: false)
        )
        XCTAssertFalse(VendorRuntime.claudeCode.warmsUp)
        XCTAssertTrue(VendorRuntime.openCode.warmsUp)
    }

    func testItIsWorthDoingOnceAndThenNotAgain() {
        XCTAssertTrue(
            shouldWarmUp(target, alreadyWarmed: [], vendorWarmsUp: true, turnInFlight: false)
        )
        XCTAssertFalse(
            shouldWarmUp(target, alreadyWarmed: [target], vendorWarmsUp: true, turnInFlight: false)
        )
    }

    func testNeverWhileTheUserIsWaitingForAnAnswer() {
        // Both would queue on the same model and both come back slower than if
        // neither had run.
        XCTAssertFalse(
            shouldWarmUp(target, alreadyWarmed: [], vendorWarmsUp: true, turnInFlight: true)
        )
    }

    func testEachThingThatChangesTheCachedPromptIsItsOwnTarget() {
        // The prefix is built from the model, and from the directory — opencode
        // reads the project's own rules files into the prompt — so warming one
        // combination does nothing for another.
        let otherModel = WarmUpTarget(
            vendorID: target.vendorID, modelID: "llamacpp/qwen3.8-27b", directory: target.directory
        )
        let otherDirectory = WarmUpTarget(
            vendorID: target.vendorID, modelID: target.modelID, directory: "/Users/me/elsewhere"
        )
        XCTAssertTrue(
            shouldWarmUp(otherModel, alreadyWarmed: [target], vendorWarmsUp: true, turnInFlight: false)
        )
        XCTAssertTrue(
            shouldWarmUp(otherDirectory, alreadyWarmed: [target], vendorWarmsUp: true, turnInFlight: false)
        )
    }

    func testInheritingAModelIsItsOwnTargetRatherThanEveryModel() {
        // "No --model" is a real configuration with its own cached prefix, not a
        // wildcard that matches whatever was warmed last.
        let inheriting = WarmUpTarget(
            vendorID: target.vendorID, modelID: nil, directory: target.directory
        )
        XCTAssertTrue(
            shouldWarmUp(inheriting, alreadyWarmed: [target], vendorWarmsUp: true, turnInFlight: false)
        )
    }

    func testTheWarmUpSendsTheSameFlagsARealTurnWould() {
        // The whole point. A warm-up that leaves out `--dir` prefills a prompt
        // no later turn will ever send, and the person still waits.
        let arguments = openCodeArguments(
            model: .some(ChatModel(id: "ollama/qwen3.8:27b-mlx", displayName: "q")),
            variant: .none(),
            session: .none(),
            workingDirectory: URL(fileURLWithPath: "/Users/me/project"),
            prompt: VendorRuntime.warmUpPrompt
        )
        XCTAssertEqual(
            arguments,
            [
                "run", "--format", "json",
                "--dir", "/Users/me/project",
                "--model", "ollama/qwen3.8:27b-mlx",
                "--", VendorRuntime.warmUpPrompt
            ]
        )
        // No `--session`: a throwaway "ready" must not land in the thread the
        // person is reading.
        XCTAssertFalse(arguments.contains("--session"))
    }
}
