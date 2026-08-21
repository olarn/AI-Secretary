import XCTest
import FunctionalCore
@testable import LLMProvider

/// Reading opencode, against output captured from the real thing.
///
/// Every fixture below is a line opencode 1.18.15 actually printed on
/// 2026-08-21, not a line written to make a parser pass. That is the difference
/// that matters here: the whole risk in this reader is believing a shape the
/// tool does not emit.
final class OpenCodeTests: XCTestCase {
    private let installation = AgentInstallation(
        vendorID: AIVendor.openCode.id,
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/opencode"),
        version: "1.18.15"
    )

    // MARK: - Fixtures, verbatim

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

    // MARK: - Reading a line

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
        // The app's textDelta means "append this". Handing back a whole part
        // that was already partly shown would print the beginning twice.
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
        // Not an extension, so there is no tail. Printing the difference would
        // print the middle of a sentence that no longer begins where the reader
        // last saw it begin.
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
        // A later opencode emitting a type this build has never seen must not
        // be able to end a turn that is otherwise going fine.
        XCTAssertEqual(openCodeReading(line: "not json at all").events, [])
        XCTAssertEqual(openCodeReading(line: #"{"type":"something_new"}"#).events, [])
        XCTAssertEqual(openCodeReading(line: "").events, [])
    }

    func testCarriedTextSurvivesALineThatSaysNothing() {
        let first = openCodeReading(line: textLine)
        let noise = openCodeReading(line: "garbage", textByPart: first.textByPart)
        XCTAssertEqual(noise.textByPart, first.textByPart)
    }

    // MARK: - The argv

    func testTheMessageIsLastAndBehindADoubleDash() {
        // A message starting with a dash is read as a flag otherwise, which is
        // the bug that made it impossible to send a bullet list on the Claude
        // path. Nothing may follow the message.
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
        // The same rule the Claude path follows: passing no `--model` is how the
        // user's own default is allowed to stand.
        let arguments = openCodeArguments(
            model: .none(), variant: .none(), session: .none(),
            workingDirectory: URL(fileURLWithPath: "/tmp/p"), prompt: "hi"
        )
        XCTAssertFalse(arguments.contains("--model"))
        XCTAssertFalse(arguments.contains("--variant"))
        XCTAssertFalse(arguments.contains("--session"))
    }

    func testTheCharactersInstructionsGoInFrontOfTheQuestion() {
        // opencode has no --append-system-prompt, so without this the persona
        // never arrived at all — the first turn driven through it carried the
        // question and nothing about who she is.
        XCTAssertEqual(
            openCodePrompt(system: .some("You are Pikachu."), message: "hello"),
            "You are Pikachu.\n\n---\n\nhello"
        )
    }

    func testNoInstructionsMeansTheMessageIsSentAsItIs() {
        XCTAssertEqual(openCodePrompt(system: .none(), message: "hello"), "hello")
        XCTAssertEqual(openCodePrompt(system: .some("   "), message: "hello"), "hello")
    }

    // MARK: - The machine's own model list

    /// Verbatim from `opencode models` on 2026-08-21.
    private let modelsOutput = """
    opencode/big-pickle
    opencode/hy3-free
    llamacpp/qwen3.8-27b
    ollama/qwen3.8:27b-mlx
    """

    func testTheModelListKeepsTheProviderPrefixInTheIDAndDropsItInTheLabel() {
        let models = openCodeModels(modelsOutput)
        XCTAssertEqual(models.count, 4)
        // `--model` wants the whole thing back…
        XCTAssertEqual(models.last?.id, "ollama/qwen3.8:27b-mlx")
        // …but a menu of eight ollama entries shouldn't read as eight "ollama"s.
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

    // MARK: - The vendor

    func testOpenCodeHidesEffortAndAsksForItsPath() {
        XCTAssertTrue(AIVendor.openCode.executableIsUserSupplied)
        // opencode's `--variant` is provider-specific and a local model ignores
        // it, so the row is hidden rather than shown and inert.
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
        // Found by driving it: switching from opencode back to Claude Code left
        // `qwen3.8:27b-mlx` sitting in the Model row under Claude Code, where it
        // is not a model that exists.
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
        // Inheriting stays inheriting — the app must not pick one on the user's
        // behalf just because the maker changed.
        XCTAssertEqual(modelSurviving(.none(), switchingTo: .openCode), Option.none())
    }

    // MARK: - Finding it

    private func locator(existing: [String]) -> OpenCodeLocator {
        OpenCodeLocator(
            isExecutable: { existing.contains($0) },
            probe: { _ in "1.18.15" }
        )
    }

    func testThePathTheUserGaveIsTheOnlyOneTried() {
        // Not a search: if the user typed a path, silently using a different
        // opencode would run work somewhere they didn't choose.
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
        // Blank is the same as unset — a field the user cleared, not a path.
        XCTAssertEqual(locator(existing: ["/opt/homebrew/bin/opencode"]).locate(userPath: "  "), found)
    }

    // MARK: - Whether it can be reached

    func testAnOpenCodeThatAnswersItsVersionIsReachable() async {
        let probe = await VendorRuntime.openCodeConnectionProbe(installation)
        XCTAssertEqual(probe, .signedIn(detail: VendorRuntime.openCodeReadyDetail))

        let shown = vendorConnection(
            vendor: .openCode, executable: .found(installation), probe: probe
        )
        // The tick must not read as though it meant what Claude's does.
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
        // It is the user's own path, so "isn't installed" would send them to
        // install something they already have.
        XCTAssertEqual(
            vendorConnection(vendor: .openCode, executable: .missing(searched: []), probe: .notRun),
            .failed("OpenCode isn't at the path given. Check the CLI path setting.")
        )
    }
}
