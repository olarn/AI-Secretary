import FunctionalCore
import XCTest
@testable import LLMProvider

// MARK: - Finding the CLI

final class ClaudeCodeLocatorTests: XCTestCase {
    private var home: String { NSHomeDirectory() }

    func testFindsTheFirstKnownPathThatIsExecutable() {
        let expected = "\(home)/.local/bin/claude"
        let locator = ClaudeCodeLocator(
            isExecutable: { $0 == expected },
            probe: { _ in "2.1.220 (Claude Code)" }
        )

        guard case .available(let installation) = locator.locate() else {
            return XCTFail("Expected to find the CLI")
        }
        XCTAssertEqual(installation.executableURL.path, expected)
        XCTAssertEqual(installation.version, "2.1.220 (Claude Code)")
    }

    /// The order matters: a Homebrew copy shouldn't win over the standard
    /// installer's location.
    func testPrefersTheStandardInstallLocationOverHomebrew() {
        let locator = ClaudeCodeLocator(
            isExecutable: { $0 == "\(self.home)/.local/bin/claude" || $0 == "/opt/homebrew/bin/claude" },
            probe: { _ in nil }
        )

        XCTAssertEqual(
            locator.locate().installation?.executableURL.path,
            "\(home)/.local/bin/claude"
        )
    }

    func testFindsAHomebrewInstallWhenTheStandardOneIsAbsent() {
        let locator = ClaudeCodeLocator(
            isExecutable: { $0 == "/opt/homebrew/bin/claude" },
            probe: { _ in nil }
        )

        XCTAssertEqual(
            locator.locate().installation?.executableURL.path,
            "/opt/homebrew/bin/claude"
        )
    }

    /// A missing version string must not disqualify an otherwise working CLI —
    /// it is only used for display.
    func testAnUnreadableVersionStillCountsAsInstalled() {
        let locator = ClaudeCodeLocator(
            isExecutable: { $0 == "/usr/local/bin/claude" },
            probe: { _ in nil }
        )

        guard case .available(let installation) = locator.locate() else {
            return XCTFail("Expected to find the CLI")
        }
        XCTAssertNil(installation.version)
    }

    func testReportsWhereItLookedWhenNothingIsInstalled() {
        let locator = ClaudeCodeLocator(isExecutable: { _ in false }, probe: { _ in nil })

        guard case .notFound(let searched) = locator.locate() else {
            return XCTFail("Expected notFound")
        }
        XCTAssertEqual(searched.count, ClaudeCodeLocator.knownPaths.count)
        XCTAssertTrue(searched.contains("\(home)/.local/bin/claude"),
                      "The tilde in the known paths must be expanded: \(searched)")
    }
}

// MARK: - Launching it

final class ClaudeCodeProviderLaunchTests: XCTestCase {
    private let installation = ClaudeCodeInstallation(
        executableURL: URL(fileURLWithPath: "/Users/someone/.local/bin/claude"),
        version: "2.1.220"
    )

    private func arguments(
        model: ChatModel? = .sonnet5,
        effort: Effort? = nil,
        resume: String? = nil,
        system: String? = nil,
        configuration: ClaudeCodeProvider.Configuration = .init()
    ) -> [String] {
        ClaudeCodeProvider.launchArguments(
            model: Option.fromOptional(model),
            effort: Option.fromOptional(effort),
            system: Option.fromOptional(system),
            resume: resume,
            configuration: configuration
        )
    }

    /// The app is a face over the user's own Claude Code. If they haven't
    /// picked a model or effort here, theirs must stand — overriding it hands
    /// them a different assistant than the one they configured.
    func testLeavesTheModelAndEffortAloneWhenTheUserHasNotChosen() {
        let args = arguments(model: nil, effort: nil)
        XCTAssertFalse(args.contains("--model"))
        XCTAssertFalse(args.contains("--effort"))
    }

    func testPassesTheChosenModel() {
        let args = arguments(model: .opus5)
        guard let index = args.firstIndex(of: "--model") else { return XCTFail("Expected --model") }
        XCTAssertEqual(args[index + 1], "claude-opus-5")
    }

    /// Previously dropped on the floor: the setting existed but was never sent.
    func testPassesTheChosenEffort() {
        let args = arguments(effort: .xhigh)
        guard let index = args.firstIndex(of: "--effort") else { return XCTFail("Expected --effort") }
        XCTAssertEqual(args[index + 1], "xhigh")
    }

    func testAsksForTheStreamingJSONProtocolWeParse() {
        let args = arguments()
        XCTAssertTrue(args.contains("-p"))
        XCTAssertTrue(args.contains("stream-json"))
        XCTAssertTrue(args.contains("--include-partial-messages"),
                      "Without this there are no token-by-token deltas")
    }

    /// `--bare` skips OAuth and keychain reads, which is the authentication the
    /// whole approach depends on. It must never be added as an optimisation.
    func testNeverPassesBareMode() {
        XCTAssertFalse(arguments().contains("--bare"))
    }

    func testStartsAFreshSessionWhenThereIsNothingToResume() {
        XCTAssertFalse(arguments().contains("--resume"))
    }

    func testResumesTheExistingSessionSoHistoryIsKept() {
        let args = arguments(resume: "abc-123")
        guard let index = args.firstIndex(of: "--resume") else {
            return XCTFail("Expected --resume")
        }
        XCTAssertEqual(args[index + 1], "abc-123")
    }

    /// Every approved project is opened for the turn, so a question spanning
    /// two of them can be answered without the user switching.
    func testOpensTheOtherApprovedFoldersWithAddDir() {
        let config = ClaudeCodeProvider.Configuration(
            additionalDirectories: [
                URL(fileURLWithPath: "/tmp/other"),
                URL(fileURLWithPath: "/tmp/third")
            ]
        )
        let args = arguments(configuration: config)
        let paths = args.indices.filter { args[$0] == "--add-dir" }.map { args[$0 + 1] }
        XCTAssertEqual(paths, ["/tmp/other", "/tmp/third"])
    }

    func testPassesNoExtraFoldersByDefault() {
        XCTAssertFalse(arguments().contains("--add-dir"))
    }

    func testPassesTheAllowlistAsCommaSeparatedRules() {
        let config = ClaudeCodeProvider.Configuration(allowedTools: ["Read", "Bash(git log *)"])
        let args = arguments(configuration: config)
        guard let index = args.firstIndex(of: "--allowedTools") else {
            return XCTFail("Expected --allowedTools")
        }
        XCTAssertEqual(args[index + 1], "Read,Bash(git log *)")
    }

    /// The default must not let Claude Code modify anything.
    func testDefaultToolsAreReadOnly() {
        let defaults = ClaudeCodeProvider.Configuration().allowedTools
        for forbidden in ["Write", "Edit", "NotebookEdit"] {
            XCTAssertFalse(defaults.contains(forbidden), "\(forbidden) must not be pre-approved")
        }
        for rule in defaults where rule.contains("Bash") {
            XCTAssertTrue(
                rule.hasPrefix("Bash(git "),
                "Only read-only git rules may be pre-approved, got: \(rule)"
            )
        }
    }

    func testAppendsTheSystemPromptWithoutReplacingClaudeCodesOwn() {
        let args = arguments(system: "You are the Secretary.")
        XCTAssertTrue(args.contains("--append-system-prompt"))
        XCTAssertFalse(args.contains("--system-prompt"),
                       "Replacing the system prompt would discard Claude Code's own behaviour")
    }

    func testOmitsAnEmptySystemPrompt() {
        XCTAssertFalse(arguments(system: "").contains("--append-system-prompt"))
    }

    // MARK: Environment

    func testStripsTheAPIKeySoTheSubscriptionIsUsed() {
        let environment = ClaudeCodeProvider.childEnvironment(for: installation)
        XCTAssertNil(environment["ANTHROPIC_API_KEY"],
                     "An inherited key would silently bill API credit for a subscription session")
    }

    func testKeepsHomeSoCredentialsAreFound() {
        let environment = ClaudeCodeProvider.childEnvironment(for: installation)
        XCTAssertEqual(environment["HOME"], ProcessInfo.processInfo.environment["HOME"])
    }

    func testPutsTheBinaryDirectoryOnThePath() {
        let environment = ClaudeCodeProvider.childEnvironment(for: installation)
        XCTAssertTrue(environment["PATH"]?.contains("/Users/someone/.local/bin") == true,
                      "Got: \(environment["PATH"] ?? "-")")
    }
}

// MARK: - Reading its output

final class ClaudeCodeProviderStreamTests: XCTestCase {
    private func makeProvider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            installation: ClaudeCodeInstallation(executableURL: URL(fileURLWithPath: "/bin/echo"))
        )
    }

    func testCapturesTheSessionIdFromInitSoTheNextTurnCanResume() {
        let provider = makeProvider()
        XCTAssertNil(provider.sessionID)

        let events = provider.handle(
            line: #"{"type":"system","subtype":"init","session_id":"c2b27988","model":"claude-opus-5"}"#
        )

        XCTAssertTrue(events.isEmpty, "init is bookkeeping, not something the user sees")
        XCTAssertEqual(provider.sessionID, "c2b27988")
    }

    func testTurnsTextDeltasIntoStreamedText() {
        let events = makeProvider().handle(
            line: #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi!"}}}"#
        )
        XCTAssertEqual(events, [.textDelta("Hi!")])
    }

    func testIgnoresNonTextDeltas() {
        let events = makeProvider().handle(
            line: #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"..."}}}"#
        )
        XCTAssertTrue(events.isEmpty)
    }

    func testReportsCompletionWithUsage() {
        let events = makeProvider().handle(
            line: #"{"type":"result","subtype":"success","stop_reason":"end_turn","usage":{"input_tokens":4,"output_tokens":107}}"#
        )
        XCTAssertEqual(
            events,
            [.completed(stopReason: .some("end_turn"), usage: .some(ChatUsage(inputTokens: 4, outputTokens: 107)))]
        )
    }

    /// The stream carries event kinds we don't model, and Claude Code adds more
    /// between releases. An unrecognised line must be skipped, never fatal.
    func testSkipsUnknownAndMalformedLines() {
        let provider = makeProvider()
        let lines = [
            #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#,
            #"{"type":"assistant","message":{"role":"assistant"}}"#,
            #"{"type":"some_future_event"}"#,
            "not json at all",
            ""
        ]
        for line in lines {
            XCTAssertTrue(provider.handle(line: line).isEmpty, "Should ignore: \(line)")
        }
    }

    /// Moving keeps the session, and this test used to assert the opposite.
    ///
    /// The belief was that Claude Code scoped session lookup to the working
    /// directory. Measured against 2.1.220 on 2026-08-06 it does not: a session
    /// created in one directory resumes from another and still remembers.
    /// Dropping it pre-emptively cost the first message's context every time a
    /// project was approved, and silently beat Chat History — a reopened
    /// conversation lost its thread on the first turn, before the resume was
    /// ever tried.
    ///
    /// Trying and failing is the better failure: a session that really is gone
    /// comes back as `.staleSession`, which starts a fresh one and says so.
    func testMovingToAnotherDirectoryKeepsTheSession() {
        let provider = makeProvider()
        provider.prepare(workingDirectory: URL(fileURLWithPath: "/tmp/scratch"), additionalDirectories: [], allowedTools: nil)
        _ = provider.handle(line: #"{"type":"system","subtype":"init","session_id":"scratch-session"}"#)
        XCTAssertEqual(provider.sessionID, "scratch-session")

        provider.prepare(workingDirectory: URL(fileURLWithPath: "/tmp/project"), additionalDirectories: [], allowedTools: nil)

        XCTAssertEqual(provider.sessionID, "scratch-session", "the thread survives the move")
    }

    /// The safety net that makes the above safe to rely on: a session that has
    /// genuinely gone is recognised, so the turn starts over and reports it
    /// instead of failing.
    func testAGoneSessionIsRecognisedFromWhatClaudeCodePrints() {
        XCTAssertTrue(ClaudeCodeProvider.isMissingSession(
            "No conversation found with session ID: 00000000-0000-0000-0000-000000000000"
        ))
        XCTAssertFalse(ClaudeCodeProvider.isMissingSession("some other failure"))
    }

    func testStayingInTheSameDirectoryKeepsTheSession() {
        let provider = makeProvider()
        let directory = URL(fileURLWithPath: "/tmp/project")
        provider.prepare(workingDirectory: directory, additionalDirectories: [], allowedTools: nil)
        _ = provider.handle(line: #"{"type":"system","subtype":"init","session_id":"keep-me"}"#)

        // Same directory, different allowlist — continuity must survive.
        provider.prepare(workingDirectory: directory, additionalDirectories: [], allowedTools: ["Read", "Write"])

        XCTAssertEqual(provider.sessionID, "keep-me")
    }

    /// Trailing-slash and `..` spellings of the same directory are the same
    /// directory; they must not look like a move.
    func testEquivalentPathSpellingsAreNotTreatedAsAMove() {
        let provider = makeProvider()
        provider.prepare(workingDirectory: URL(fileURLWithPath: "/tmp/project"), additionalDirectories: [], allowedTools: nil)
        _ = provider.handle(line: #"{"type":"system","subtype":"init","session_id":"keep-me"}"#)

        provider.prepare(workingDirectory: URL(fileURLWithPath: "/tmp/other/../project"), additionalDirectories: [], allowedTools: nil)

        XCTAssertEqual(provider.sessionID, "keep-me")
    }

    func testRecognisesTheMissingSessionErrorClaudeCodeReports() {
        XCTAssertTrue(ClaudeCodeProvider.isMissingSession(
            "No conversation found with session ID: ad7ed7bc-8b88-4c08-aaec-13fa733094e6"
        ))
        XCTAssertFalse(ClaudeCodeProvider.isMissingSession("Invalid API key"))
        XCTAssertFalse(ClaudeCodeProvider.isMissingSession(""))
    }

    func testResettingTheSessionStartsAFreshConversation() {
        let provider = makeProvider()
        _ = provider.handle(line: #"{"type":"system","subtype":"init","session_id":"abc"}"#)
        XCTAssertEqual(provider.sessionID, "abc")

        provider.resetSession()
        XCTAssertNil(provider.sessionID)
    }
}

// MARK: - Refusals

final class ClaudeCodeRefusalTests: XCTestCase {
    private func makeProvider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            installation: ClaudeCodeInstallation(executableURL: URL(fileURLWithPath: "/bin/echo"))
        )
    }

    /// The refusal only carries the tool_use id, so the earlier assistant turn
    /// has to be remembered to say what was actually blocked.
    func testPairsARefusalWithTheCallItRefused() {
        let provider = makeProvider()
        _ = provider.handle(line: #"""
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Write","input":{"file_path":"/tmp/p/out.txt","content":"x"}}]}}
        """#)

        let events = provider.handle(line: #"""
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","is_error":true,"content":"Claude requested permissions to write to /tmp/p/out.txt, but you haven't granted it yet."}]}}
        """#)

        XCTAssertEqual(events, [.toolDenied(DeniedTool(name: "Write", target: .some("/tmp/p/out.txt"), rules: ["Write"]))])
    }

    /// An ordinary tool failure is not a permission problem — offering to widen
    /// permissions for a missing file would be nonsense.
    func testAnOrdinaryToolErrorIsNotTreatedAsARefusal() {
        let provider = makeProvider()
        _ = provider.handle(line: #"""
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_2","name":"Read","input":{"file_path":"/tmp/nope"}}]}}
        """#)

        let events = provider.handle(line: #"""
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_2","is_error":true,"content":"File does not exist."}]}}
        """#)

        XCTAssertTrue(events.isEmpty)
    }

    func testASuccessfulToolResultEmitsNothing() {
        let provider = makeProvider()
        _ = provider.handle(line: #"""
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Read","input":{}}]}}
        """#)
        let events = provider.handle(line: #"""
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"contents"}]}}
        """#)
        XCTAssertTrue(events.isEmpty)
    }

    /// Approving one command must not hand over the whole shell.
    func testABashRefusalNarrowsToTheCommandThatWasTried() {
        let denied = ClaudeCodeProvider.describe(tool: "Bash", input: ["command": "npm test --watch=false"])
        XCTAssertEqual(denied.rules, ["Bash(npm test *)"])
        XCTAssertEqual(denied.target, .some("npm test --watch=false"))
    }

    func testAFileToolRuleIsJustTheToolName() {
        let denied = ClaudeCodeProvider.describe(tool: "Edit", input: ["file_path": "/tmp/a.txt"])
        XCTAssertEqual(denied.rules, ["Edit"])
        XCTAssertEqual(denied.summary, "Edit: /tmp/a.txt")
    }

    func testRecognisesThePhrasesClaudeCodeUsesForRefusals() {
        for message in [
            "Claude requested permissions to write to /tmp/x, but you haven't granted it yet.",
            "This command requires approval",
            "Claude requested permissions to edit /tmp/y which is a sensitive file."
        ] {
            XCTAssertTrue(ClaudeCodeProvider.isPermissionRefusal(message), "Missed: \(message)")
        }
        XCTAssertFalse(ClaudeCodeProvider.isPermissionRefusal("File does not exist."))
    }

    /// A command with more than one operation is refused in the plural, which
    /// is not a substring of the singular. Missing it meant the app read the
    /// refusal as an ordinary failure and offered nothing — the owner's
    /// `cd … && python3 …` had no way forward at all.
    ///
    /// Copied from Claude Code 2.1.229 rather than paraphrased.
    func testTheRefusalForACommandWithSeveralOperationsIsRecognised() {
        XCTAssertTrue(ClaudeCodeProvider.isPermissionRefusal(
            "This Bash command contains multiple operations. The following parts "
            + "require approval: cd \"/Users/o/TISCO - AI Sharing\", python3 -c \"import pptx\""
        ))
    }

    /// Being sent outside the working directory is refused too, but no rule
    /// widens it — it needs a different directory, not a permission. Reading it
    /// as widenable would offer a grant that changes nothing.
    func testBeingBlockedFromLeavingTheWorkingDirectoryIsNotAPermissionToWiden() {
        XCTAssertFalse(ClaudeCodeProvider.isPermissionRefusal(
            "cd in '/Users/o/elsewhere' was blocked. For security, Claude Code may "
            + "only change directories to the allowed working directory."
        ))
    }
}

// MARK: - Choosing a model

final class ChatModelChoiceTests: XCTestCase {
    /// Claude Opus 5 is the current flagship and a common Claude Code default;
    /// it was missing from the allowlist, so `/model claude-opus-5` was refused.
    func testOpus5IsSelectable() {
        XCTAssertEqual(ChatModel.named("claude-opus-5"), .some(.opus5))
        XCTAssertTrue(ChatModel.known.contains(.opus5))
    }

    /// The short names Claude Code accepts should work here too.
    func testShortNamesResolveToTheCurrentModelOfThatFamily() {
        XCTAssertEqual(ChatModel.named("opus"), .some(.opus5))
        XCTAssertEqual(ChatModel.named("sonnet"), .some(.sonnet5))
        XCTAssertEqual(ChatModel.named("fable"), .some(.fable5))
        XCTAssertEqual(ChatModel.named("haiku"), .some(.haiku45))
        XCTAssertEqual(ChatModel.named("OPUS"), .some(.opus5), "Case shouldn't matter")
    }

    func testDefaultMeansInheritRatherThanAModel() {
        XCTAssertTrue(ChatModel.meansInherit("default"))
        XCTAssertTrue(ChatModel.meansInherit("auto"))
        XCTAssertFalse(ChatModel.meansInherit("opus"))
        XCTAssertEqual(ChatModel.named("default"), Option.none(), "It isn't a model")
    }

    func testAnUnknownNameIsStillRejected() {
        XCTAssertEqual(ChatModel.named("gpt-4"), Option.none())
        XCTAssertFalse(ChatModel.meansInherit("gpt-4"))
    }
}

// MARK: - Reading the user's own configuration

final class ClaudeCodeDefaultsTests: XCTestCase {
    private func parse(_ json: String) -> ClaudeCodeDefaults {
        ClaudeCodeDefaults.parse(Data(json.utf8))
    }

    /// The settings panel names a real model rather than "your default", so the
    /// alias Claude Code stores has to resolve.
    func testResolvesTheAliasClaudeCodeStores() {
        let defaults = parse(#"{"model":"opus","effortLevel":"medium"}"#)
        XCTAssertEqual(defaults.model, .some(.opus5))
        XCTAssertEqual(defaults.effort, .some(.medium))
    }

    func testAcceptsAFullModelID() {
        XCTAssertEqual(parse(#"{"model":"claude-sonnet-5"}"#).model, .some(.sonnet5))
    }

    /// Not knowing is fine — it just means we can't name it yet.
    func testMissingOrUnreadableSettingsAreNotAnError() {
        XCTAssertEqual(parse(#"{"hooks":{}}"#), .unknown)
        XCTAssertEqual(parse("not json"), .unknown)
        XCTAssertEqual(ClaudeCodeDefaults.read(from: URL(fileURLWithPath: "/nope/settings.json")), .unknown)
    }

    func testAnUnrecognisedModelNameIsIgnoredRatherThanGuessed() {
        XCTAssertEqual(parse(#"{"model":"some-future-model"}"#).model, Option.none())
    }

    /// The live session is authoritative — it reports what actually ran.
    func testASessionReportsTheModelItResolvedTo() {
        let provider = ClaudeCodeProvider(
            installation: ClaudeCodeInstallation(executableURL: URL(fileURLWithPath: "/bin/echo"))
        )
        XCTAssertNil(provider.reportedModel)
        _ = provider.handle(line: #"{"type":"system","subtype":"init","session_id":"s","model":"claude-opus-5"}"#)
        XCTAssertEqual(provider.reportedModel, "claude-opus-5")
    }
}

// MARK: - Showing what it's doing

final class AgentActivityTests: XCTestCase {
    private func makeProvider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            installation: ClaudeCodeInstallation(executableURL: URL(fileURLWithPath: "/bin/echo"))
        )
    }

    /// A thinking block opening is the only usable signal that reasoning is
    /// happening — its deltas carry no text on this model family.
    func testAThinkingBlockOpeningIsReportedAsActivity() {
        let events = makeProvider().handle(
            line: #"{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"thinking","thinking":""}}}"#
        )
        XCTAssertEqual(events, [.activity(AgentActivity(kind: .thinking, detail: "Thinking"))])
    }

    func testAToolCallIsReportedWithWhatItIsActingOn() {
        let events = makeProvider().handle(line: #"""
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/tmp/p/about.md"}}]}}
        """#)
        XCTAssertEqual(events, [.activity(AgentActivity(kind: .tool, detail: "Read: about.md"))])
    }

    func testAWebSearchShowsTheQuery() {
        XCTAssertEqual(
            ClaudeCodeProvider.activityDetail(tool: "WebSearch", input: ["query": "On Cloud ราคา"]),
            "WebSearch: On Cloud ราคา"
        )
    }

    func testALongArgumentIsTruncatedSoTheLineStaysReadable() {
        let detail = ClaudeCodeProvider.activityDetail(
            tool: "Bash",
            input: ["command": String(repeating: "x", count: 200)]
        )
        XCTAssertTrue(detail.hasSuffix("…"))
        XCTAssertLessThan(detail.count, 80)
    }

    func testAToolWithNothingWorthShowingIsJustItsName() {
        XCTAssertEqual(ClaudeCodeProvider.activityDetail(tool: "Glob", input: [:]), "Glob")
    }
}

// MARK: - The PATH handed to Claude Code

/// A Finder-launched app inherits launchd's environment, where PATH is unset.
/// Claude Code itself is found by absolute path, but the programs *it* launches
/// are not: a stdio MCP server configured as `node …/index.js` reported
/// `status: "failed"` from the packaged app and `connected` from a terminal.
final class LoginShellPathTests: XCTestCase {
    private let binary = "/Users/someone/.local/bin"

    func testTheUsersOwnPathIsIncluded() {
        let merged = LoginShellPath.merged(
            binaryDirectory: binary,
            loginPath: .some("/Users/someone/.nvm/versions/node/v22.16.0/bin:/opt/homebrew/bin"),
            inherited: .some("/usr/bin:/bin")
        )
        XCTAssertTrue(merged.contains("/Users/someone/.nvm/versions/node/v22.16.0/bin"),
                      "node has to be reachable or stdio MCP servers can't start: \(merged)")
        XCTAssertTrue(merged.contains("/opt/homebrew/bin"))
    }

    func testTheBinaryDirectoryComesFirst() {
        let merged = LoginShellPath.merged(
            binaryDirectory: binary, loginPath: .some("/opt/homebrew/bin"), inherited: Option.none()
        )
        XCTAssertTrue(merged.hasPrefix(binary + ":"), "Got: \(merged)")
    }

    func testTheSystemMinimumIsAlwaysThere() {
        let merged = LoginShellPath.merged(binaryDirectory: binary, loginPath: Option.none(), inherited: Option.none())
        for directory in ["/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            XCTAssertTrue(merged.contains(directory), "Missing \(directory) in \(merged)")
        }
    }

    /// A shell that won't answer must not leave the child with nothing usable.
    func testAnUnavailableLoginShellStillLeavesAWorkingPath() {
        let merged = LoginShellPath.merged(
            binaryDirectory: binary, loginPath: Option.none(), inherited: .some("/usr/bin:/bin")
        )
        XCTAssertTrue(merged.contains(binary))
        XCTAssertTrue(merged.contains("/usr/bin"))
    }

    func testDirectoriesAreNotRepeated() {
        let merged = LoginShellPath.merged(
            binaryDirectory: "/usr/bin",
            loginPath: .some("/usr/bin:/opt/homebrew/bin"),
            inherited: .some("/usr/bin:/bin")
        )
        let occurrences = merged.split(separator: ":").filter { $0 == "/usr/bin" }
        XCTAssertEqual(occurrences.count, 1, "Got: \(merged)")
    }

    func testTheChildEnvironmentCarriesIt() {
        let environment = ClaudeCodeProvider.childEnvironment(
            for: ClaudeCodeInstallation(executableURL: URL(fileURLWithPath: "\(binary)/claude")),
            loginPath: .some("/Users/someone/.nvm/versions/node/v22.16.0/bin")
        )
        XCTAssertTrue(environment["PATH"]?.contains(".nvm") == true, "Got: \(environment["PATH"] ?? "-")")
        XCTAssertNil(environment["ANTHROPIC_API_KEY"], "Still stripped")
    }
}
