import XCTest
import FunctionalCore
@testable import LLMProvider

final class OpenCodeTests: XCTestCase {
    private let installation = AgentInstallation(
        vendorID: AIVendor.openCode.id,
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/opencode"),
        version: "1.18.15"
    )

    private let stepStart = #"""
    {"type":"step_start","timestamp":1787286175449,"sessionID":"ses_fdd73a357ffebmWk58LsC19g4b","part":{"id":"prt_0228ebecf001j0NhzsEQaI3O5i","messageID":"msg_0228c5da7001raAnDQ5YLcdOj6","sessionID":"ses_fdd73a357ffebmWk58LsC19g4b","type":"step-start"}}
    """#

    private let textLine = #"""
    {"type":"text","timestamp":1787286176167,"sessionID":"ses_fdd73a357ffebmWk58LsC19g4b","part":{"id":"prt_0228ec1970017BiNnzhrhNZ7RD","messageID":"msg_0228c5da7001raAnDQ5YLcdOj6","sessionID":"ses_fdd73a357ffebmWk58LsC19g4b","type":"text","text":"pong","time":{"start":1787286176151,"end":1787286176153}}}
    """#

    private let toolLine = #"""
    {"type":"tool_use","timestamp":1787286264096,"sessionID":"ses_fdd70d533ffeW4uSjNmHNA1BJa","part":{"type":"tool","tool":"read","callID":"call_fbhedrjt","state":{"status":"completed","input":{"filePath":"/Users/Olarn/tmp/ocspike"},"title":"Users/Olarn/tmp/ocspike","time":{"start":1,"end":2}},"id":"prt_022901910001fMLKxgKR6gWA0S","sessionID":"ses_fdd70d533ffeW4uSjNmHNA1BJa","messageID":"msg_0228f2bc9001I6kqJFJ0bKLHrS"}}
    """#

    private let stepFinish = #"""
    {"type":"step_finish","timestamp":1787286176167,"sessionID":"ses_fdd73a357ffebmWk58LsC19g4b","part":{"id":"prt_0228ec19b0014SzvaQps3BWDT3","reason":"stop","messageID":"msg_0228c5da7001raAnDQ5YLcdOj6","sessionID":"ses_fdd73a357ffebmWk58LsC19g4b","type":"step-finish","tokens":{"total":13151,"input":13127,"output":24,"reasoning":0,"cache":{"write":0,"read":0}},"cost":0}}
    """#

    func testAStepStartOpensATextBlock() {
        let reading = openCodeReading(line: stepStart)
        XCTAssertEqual(reading.events, [.textBlockBegan])
        XCTAssertEqual(reading.sessionID, Option.some("ses_fdd73a357ffebmWk58LsC19g4b"))
    }

    func testTextArrivesAsADelta() {
        let reading = openCodeReading(line: textLine)
        XCTAssertEqual(reading.events, [.textDelta("pong")])
        XCTAssertEqual(reading.textByPart["prt_0228ec1970017BiNnzhrhNZ7RD"], "pong")
    }

    func testAResentPartOnlyYieldsItsNewTail() {
        let first = openCodeReading(line: textLine)
        let grown = textLine.replacingOccurrences(of: #""text":"pong""#, with: #""text":"pong and more""#)
        let second = openCodeReading(line: grown, textByPart: first.textByPart)
        XCTAssertEqual(second.events, [.textDelta(" and more")])
    }

    func testAnUnchangedResendSaysNothingAtAll() {
        let first = openCodeReading(line: textLine)
        let again = openCodeReading(line: textLine, textByPart: first.textByPart)
        XCTAssertEqual(again.events, [])
    }

    func testARewrittenPartIsSentWholeRatherThanAsAFragment() {
        let first = openCodeReading(line: textLine)
        let rewritten = textLine.replacingOccurrences(of: #""text":"pong""#, with: #""text":"actually, ping""#)
        let second = openCodeReading(line: rewritten, textByPart: first.textByPart)
        XCTAssertEqual(second.events, [.textDelta("actually, ping")])
    }

    func testAToolCallIsNamedByWhatItTouched() {
        let reading = openCodeReading(line: toolLine)
        XCTAssertEqual(
            reading.events,
            [.activity(AgentActivity(kind: .tool, detail: "read: Users/Olarn/tmp/ocspike"))]
        )
    }

    func testAToolWithNoTitleFallsBackToItsName() {
        XCTAssertEqual(openCodeToolLabel(["tool": "bash"]), "bash")
        XCTAssertEqual(openCodeToolLabel(["tool": "bash", "state": ["title": "  "]]), "bash")
    }

    func testStepFinishCarriesTheTokensAndSaysNothingOnScreen() {
        let reading = openCodeReading(line: stepFinish)
        XCTAssertEqual(reading.events, [])
        XCTAssertEqual(
            reading.usage,
            Option.some(ChatUsage(inputTokens: 13127, outputTokens: 24, cacheWriteTokens: 0, cacheReadTokens: 0, costUSD: 0))
        )
    }

    func testAnUnreadableLineIsNothingHappenedRatherThanAFailure() {
        XCTAssertEqual(openCodeReading(line: "not json at all").events, [])
        XCTAssertEqual(openCodeReading(line: #"{"type":"something_new"}"#).events, [])
        XCTAssertEqual(openCodeReading(line: "").events, [])
    }

    func testCarriedTextSurvivesALineThatSaysNothing() {
        let first = openCodeReading(line: textLine)
        let noise = openCodeReading(line: "garbage", textByPart: first.textByPart)
        XCTAssertEqual(noise.textByPart, first.textByPart)
    }

    func testTheMessageIsLastAndBehindADoubleDash() {
        let arguments = openCodeArguments(
            model: .none(), variant: .none(), session: .none(),
            workingDirectory: nil, prompt: "- a bullet"
        )
        XCTAssertEqual(arguments, ["run", "--format", "json", "--", "- a bullet"])
        XCTAssertEqual(arguments.last, "- a bullet")
        XCTAssertEqual(arguments[arguments.count - 2], "--")
    }

    func testEveryChosenThingReachesTheCommandLine() {
        let arguments = openCodeArguments(
            model: .some(ChatModel(id: "ollama/qwen3.8:27b-mlx", displayName: "qwen3.8:27b-mlx")),
            variant: .some("high"),
            session: .some("ses_123"),
            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
            prompt: "hello"
        )
        XCTAssertEqual(
            arguments,
            [
                "run", "--format", "json",
                "--dir", "/tmp/project",
                "--model", "ollama/qwen3.8:27b-mlx",
                "--variant", "high",
                "--session", "ses_123",
                "--", "hello"
            ]
        )
    }

    func testNothingChosenMeansNoFlagAtAll() {
        let arguments = openCodeArguments(
            model: .none(), variant: .none(), session: .none(),
            workingDirectory: URL(fileURLWithPath: "/tmp/p"), prompt: "hi"
        )
        XCTAssertFalse(arguments.contains("--model"))
        XCTAssertFalse(arguments.contains("--variant"))
        XCTAssertFalse(arguments.contains("--session"))
    }

    func testTheCharactersInstructionsGoInFrontOfTheQuestion() {
        XCTAssertEqual(
            openCodePrompt(system: .some("You are Pikachu."), message: "hello"),
            "You are Pikachu.\n\n---\n\nhello"
        )
    }

    func testNoInstructionsMeansTheMessageIsSentAsItIs() {
        XCTAssertEqual(openCodePrompt(system: .none(), message: "hello"), "hello")
        XCTAssertEqual(openCodePrompt(system: .some("   "), message: "hello"), "hello")
    }

    private let modelsOutput = """
    opencode/big-pickle
    opencode/hy3-free
    llamacpp/qwen3.8-27b
    ollama/qwen3.8:27b-mlx
    """

    func testTheModelListKeepsTheProviderPrefixInTheIDAndDropsItInTheLabel() {
        let models = openCodeModels(modelsOutput)
        XCTAssertEqual(models.count, 4)
        XCTAssertEqual(models.last?.id, "ollama/qwen3.8:27b-mlx")
        XCTAssertEqual(models.last?.displayName, "qwen3.8:27b-mlx")
    }

    func testLinesThatAreNotAModelAreSkipped() {
        XCTAssertEqual(openCodeModels("").count, 0)
        XCTAssertEqual(openCodeModels("some banner text\n\nollama/x").map(\.id), ["ollama/x"])
    }

    func testAMakerWithAFixedListNeedsNoDiscovery() async {
        let offered = await VendorRuntime.claudeCode.offeredModels(installation)
        XCTAssertEqual(offered, ChatModel.known)
    }

    func testDiscoveryComingBackEmptyFallsBackRatherThanShowingNothing() async {
        let runtime = VendorRuntime(
            vendor: .claudeCode,
            makeProvider: VendorRuntime.claudeCode.makeProvider,
            probe: { _ in .notRun },
            discoverModels: { _ in [] }
        )
        let offered = await runtime.offeredModels(installation)
        XCTAssertEqual(offered, ChatModel.known)
    }

    func testOpenCodeHidesEffortAndAsksForItsPath() {
        XCTAssertTrue(AIVendor.openCode.executableIsUserSupplied)
        XCTAssertFalse(AIVendor.openCode.supportsEffort)
        XCTAssertFalse(AIVendor.openCode.supportsBrowser)
        XCTAssertFalse(AIVendor.openCode.supportsSkills)
    }

    func testBothMakersAreOfferedWithClaudeFirst() {
        XCTAssertEqual(AIVendor.known.map(\.id), ["claude-code", "opencode"])
        XCTAssertEqual(VendorRuntime.all.map(\.vendor.id), ["claude-code", "opencode"])
        XCTAssertEqual(VendorRuntime.named("opencode").map(\.vendor)^, Option.some(AIVendor.openCode))
    }

    func testAModelBelongingToTheOldMakerDoesNotSurviveTheSwitch() {
        let openCodeModel = ChatModel(id: "ollama/qwen3.8:27b-mlx", displayName: "qwen3.8:27b-mlx")
        XCTAssertEqual(
            modelSurviving(.some(openCodeModel), switchingTo: .claudeCode),
            Option.none()
        )
    }

    func testAModelTheNewMakerOffersIsKept() {
        XCTAssertEqual(
            modelSurviving(.some(ChatModel.opus5), switchingTo: .claudeCode),
            Option.some(ChatModel.opus5)
        )
        XCTAssertEqual(modelSurviving(.none(), switchingTo: .openCode), Option.none())
    }

    private func locator(existing: [String]) -> OpenCodeLocator {
        OpenCodeLocator(
            isExecutable: { existing.contains($0) },
            probe: { _ in "1.18.15" }
        )
    }

    func testThePathTheUserGaveIsTheOnlyOneTried() {
        let found = locator(existing: ["/opt/homebrew/bin/opencode", "/custom/opencode"])
            .locate(userPath: "/custom/opencode")
        XCTAssertEqual(found.map(\.executableURL.path)^, Option.some("/custom/opencode"))
    }

    func testABadPathIsAbsentEvenThoughOneExistsElsewhere() {
        let found = locator(existing: ["/opt/homebrew/bin/opencode"]).locate(userPath: "/typo/opencode")
        XCTAssertEqual(found, Option.none())
    }

    func testWithNoPathGivenTheUsualPlacesAreSearched() {
        let found = locator(existing: ["/opt/homebrew/bin/opencode"]).locate(userPath: nil)
        XCTAssertEqual(found.map(\.executableURL.path)^, Option.some("/opt/homebrew/bin/opencode"))
        XCTAssertEqual(found.map(\.vendorID)^, Option.some("opencode"))
        XCTAssertEqual(locator(existing: ["/opt/homebrew/bin/opencode"]).locate(userPath: "  "), found)
    }

    func testAnOpenCodeThatAnswersItsVersionIsReachable() async {
        let probe = await VendorRuntime.openCodeConnectionProbe(installation)
        XCTAssertEqual(probe, .signedIn(detail: VendorRuntime.openCodeReadyDetail))

        let shown = vendorConnection(
            vendor: .openCode, executable: .found(installation), probe: probe
        )
        XCTAssertEqual(shown, .connected("OpenCode · 1.18.15 · runs · no approval cards"))
    }

    func testAFileThatIsNotOpenCodeIsRefusedWithThePathToFix() async {
        let notOpenCode = AgentInstallation(
            vendorID: AIVendor.openCode.id,
            executableURL: URL(fileURLWithPath: "/bin/ls"),
            version: nil
        )
        let probe = await VendorRuntime.openCodeConnectionProbe(notOpenCode)
        XCTAssertEqual(
            probe,
            .refused("That file didn't answer `opencode --version`. Check the CLI path.")
        )
    }

    func testAMissingOpenCodeSaysCheckThePathNotNotInstalled() {
        XCTAssertEqual(
            vendorConnection(vendor: .openCode, executable: .missing(searched: []), probe: .notRun),
            .failed("OpenCode isn't at the path given. Check the CLI path setting.")
        )
    }
}
