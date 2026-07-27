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
        XCTAssertFalse(
            defaults.contains(where: { $0 == "Bash" || $0.hasPrefix("Bash(") == false && $0.contains("Bash") }),
            "Bash must only appear as narrow read-only git rules: \(defaults)"
        )
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

    func testResettingTheSessionStartsAFreshConversation() {
        let provider = makeProvider()
        _ = provider.handle(line: #"{"type":"system","subtype":"init","session_id":"abc"}"#)
        XCTAssertEqual(provider.sessionID, "abc")

        provider.resetSession()
        XCTAssertNil(provider.sessionID)
    }
}
