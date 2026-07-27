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
        resume: String? = nil,
        system: String? = nil,
        configuration: ClaudeCodeProvider.Configuration = .init()
    ) -> [String] {
        ClaudeCodeProvider.arguments(
            prompt: "hello",
            model: .sonnet5,
            system: system,
            resume: resume,
            configuration: configuration
        )
    }

    func testAsksForTheStreamingJSONProtocolWeParse() {
        let args = arguments()
        XCTAssertEqual(args.first, "-p")
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
        XCTAssertEqual(events, [.completed(stopReason: "end_turn", usage: ChatUsage(inputTokens: 4, outputTokens: 107))])
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

    /// Claude Code scopes session lookup to the working directory, so a session
    /// started in the scratch directory cannot be resumed from inside a project.
    /// Carrying the id across the move produced "No conversation found with
    /// session ID" on the first message after approving a project.
    func testMovingToAnotherDirectoryDropsTheSession() {
        let provider = makeProvider()
        provider.prepare(workingDirectory: URL(fileURLWithPath: "/tmp/scratch"), additionalDirectories: [], allowedTools: nil)
        _ = provider.handle(line: #"{"type":"system","subtype":"init","session_id":"scratch-session"}"#)
        XCTAssertEqual(provider.sessionID, "scratch-session")

        provider.prepare(workingDirectory: URL(fileURLWithPath: "/tmp/project"), additionalDirectories: [], allowedTools: nil)

        XCTAssertNil(provider.sessionID, "A session from another directory can't be resumed")
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
