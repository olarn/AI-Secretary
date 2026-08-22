import XCTest
import FunctionalCore
@testable import LLMProvider

final class VendorWarmUpTests: XCTestCase {
    private let target = WarmUpTarget(
        vendorID: "opencode",
        modelID: "ollama/qwen3.8:27b-mlx",
        directory: "/Users/me/project"
    )

    func testAMakerWithNothingToWarmIsNeverWarmed() {
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
        XCTAssertFalse(
            shouldWarmUp(target, alreadyWarmed: [], vendorWarmsUp: true, turnInFlight: true)
        )
    }

    func testEachThingThatChangesTheCachedPromptIsItsOwnTarget() {
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
        let inheriting = WarmUpTarget(
            vendorID: target.vendorID, modelID: nil, directory: target.directory
        )
        XCTAssertTrue(
            shouldWarmUp(inheriting, alreadyWarmed: [target], vendorWarmsUp: true, turnInFlight: false)
        )
    }

    func testTheWarmUpSendsTheSameFlagsARealTurnWould() {
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
        XCTAssertFalse(arguments.contains("--session"))
    }
}
