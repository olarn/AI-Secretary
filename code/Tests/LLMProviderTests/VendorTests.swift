import XCTest
import FunctionalCore
@testable import LLMProvider

/// What a maker says it can do, and how "can we reach it" is decided.
final class VendorTests: XCTestCase {
    private let installation = AgentInstallation(
        vendorID: AIVendor.claudeCode.id,
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
        version: "2.1.234"
    )

    // MARK: - The descriptor

    func testClaudeCodeReadsItsModelsFromTheOneList() {
        // The point of reading rather than copying: a model added to
        // `ChatModel.known` must appear here without anyone editing the vendor.
        XCTAssertEqual(AIVendor.claudeCode.models, ChatModel.known)
        XCTAssertTrue(AIVendor.claudeCode.offers(model: ChatModel.opus5))
    }

    func testClaudeCodeIsFoundRatherThanSuppliedByHand() {
        XCTAssertFalse(AIVendor.claudeCode.executableIsUserSupplied)
        XCTAssertTrue(AIVendor.claudeCode.supportsEffort)
        XCTAssertTrue(AIVendor.claudeCode.supportsBrowser)
        XCTAssertTrue(AIVendor.claudeCode.supportsSkills)
    }

    func testAnUnknownMakerIsAbsentRatherThanACrash() {
        XCTAssertEqual(AIVendor.named("claude-code"), Option.some(AIVendor.claudeCode))
        XCTAssertEqual(AIVendor.named("gemini-cli"), Option.none())
        XCTAssertEqual(VendorRuntime.named("gemini-cli").isDefined, false)
    }

    func testAModelBelongingToAnotherMakerIsSimplyNotOffered() {
        let local = AIVendor(
            id: "opencode",
            displayName: "OpenCode",
            models: [],
            supportsEffort: false,
            supportsBrowser: false,
            supportsSkills: false,
            executableIsUserSupplied: true
        )
        XCTAssertFalse(local.offers(model: ChatModel.opus5))
    }

    func testAClaudeInstallationConvertsToTheNeutralShape() {
        let claude = ClaudeCodeInstallation(
            executableURL: URL(fileURLWithPath: "/usr/local/bin/claude"),
            version: "2.1.234"
        )
        XCTAssertEqual(claude.agent.vendorID, AIVendor.claudeCode.id)
        XCTAssertEqual(claude.agent.executableURL, claude.executableURL)
        XCTAssertEqual(claude.agent.version, "2.1.234")
    }

    // MARK: - The decision

    func testStillSearchingIsCheckingAndNotAFailure() {
        XCTAssertEqual(
            vendorConnection(vendor: .claudeCode, executable: .searching, probe: .notRun),
            .checking
        )
    }

    func testAMissingToolOutranksAnyProbeResult() {
        // The order matters: saying "not signed in" about a tool that isn't
        // installed sends the user to fix the wrong thing.
        let answer = vendorConnection(
            vendor: .claudeCode,
            executable: .missing(searched: ["/usr/local/bin/claude"]),
            probe: .signedIn(detail: "Max")
        )
        XCTAssertEqual(
            answer,
            .failed(
                "Claude Code isn't installed, or isn't where the app looked. Looked in: /usr/local/bin/claude."
            )
        )
    }

    func testAMakerWhosePathTheUserGivesIsToldToCheckThePath() {
        let local = AIVendor(
            id: "opencode",
            displayName: "OpenCode",
            models: [],
            supportsEffort: false,
            supportsBrowser: false,
            supportsSkills: false,
            executableIsUserSupplied: true
        )
        XCTAssertEqual(
            vendorConnection(vendor: local, executable: .missing(searched: []), probe: .notRun),
            .failed("OpenCode isn't at the path given. Check the CLI path setting.")
        )
    }

    func testFoundButUnaskedIsNeverATick() {
        // The whole reason this type exists: presence on disk is not proof the
        // tool can be reached, and a tick that means "found" is the false
        // "Ready" this replaces.
        XCTAssertEqual(
            vendorConnection(vendor: .claudeCode, executable: .found(installation), probe: .notRun),
            .checking
        )
    }

    func testTheVersionIsTheNumberAndNotTheProductNameAgain() {
        // `claude --version` answers "2.1.238 (Claude Code)", and the maker's
        // name is already the first thing on the line — printed whole it read
        // "Claude Code · 2.1.238 (Claude Code) · Max".
        XCTAssertEqual(versionNumber("2.1.238 (Claude Code)"), "2.1.238")
        XCTAssertEqual(versionNumber("2.1.238"), "2.1.238")
        XCTAssertEqual(versionNumber(""), "")

        let wordy = AgentInstallation(
            vendorID: AIVendor.claudeCode.id,
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            version: "2.1.238 (Claude Code)"
        )
        XCTAssertEqual(
            vendorConnection(
                vendor: .claudeCode, executable: .found(wordy), probe: .signedIn(detail: "Max")
            ),
            .connected("Claude Code · 2.1.238 · Max")
        )
    }

    func testASignedInProbeReadsNameThenVersionThenPlan() {
        XCTAssertEqual(
            vendorConnection(
                vendor: .claudeCode,
                executable: .found(installation),
                probe: .signedIn(detail: "Max")
            ),
            .connected("Claude Code · 2.1.234 · Max")
        )
    }

    func testTheSummaryDropsThePartsItDoesNotKnow() {
        let noVersion = AgentInstallation(
            vendorID: AIVendor.claudeCode.id,
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude")
        )
        XCTAssertEqual(
            vendorConnection(
                vendor: .claudeCode,
                executable: .found(noVersion),
                probe: .signedIn(detail: "")
            ),
            .connected("Claude Code")
        )
    }

    func testARefusalIsPassedThroughInTheMakersOwnWords() {
        XCTAssertEqual(
            vendorConnection(
                vendor: .claudeCode,
                executable: .found(installation),
                probe: .refused("Claude Code isn't signed in.")
            ),
            .failed("Claude Code isn't signed in.")
        )
    }

    // MARK: - What the view is allowed to ask

    func testTheViewGetsOneAnswerPerState() {
        XCTAssertNil(VendorConnection.unchecked.message)
        XCTAssertEqual(VendorConnection.checking.message, "Checking…")
        XCTAssertTrue(VendorConnection.checking.isChecking)
        XCTAssertEqual(VendorConnection.connected("ok").message, "ok")
        XCTAssertTrue(VendorConnection.connected("ok").isConnected)
        XCTAssertFalse(VendorConnection.connected("ok").isFailed)
        XCTAssertEqual(VendorConnection.failed("bad").message, "bad")
        XCTAssertTrue(VendorConnection.failed("bad").isFailed)
        XCTAssertFalse(VendorConnection.failed("bad").isConnected)
        XCTAssertFalse(VendorConnection.unchecked.isChecking)
    }

    // MARK: - Reading `claude auth status`

    /// Real output, captured from `claude auth status` on 2026-08-21. The email
    /// and organisation are in it and must never come back out — the assertion
    /// below is what keeps that true.
    private let signedInReply = """
    {
      "loggedIn": true,
      "authMethod": "claude.ai",
      "apiProvider": "firstParty",
      "email": "someone@example.com",
      "orgId": "44a67ecd-6f59-4d30-916a-706a9aa450d8",
      "orgName": "someone@example.com's Organization",
      "subscriptionType": "max"
    }
    """

    func testASignedInReplyYieldsOnlyThePlan() {
        XCTAssertEqual(claudeCodeAuthProbe(signedInReply), .signedIn(detail: "Max"))
    }

    func testNothingPrivateEscapesTheProbe() {
        let answer = vendorConnection(
            vendor: .claudeCode,
            executable: .found(installation),
            probe: claudeCodeAuthProbe(signedInReply)
        )
        let shown = answer.message ?? ""
        XCTAssertFalse(shown.contains("example.com"))
        XCTAssertFalse(shown.contains("44a67ecd"))
        XCTAssertEqual(shown, "Claude Code · 2.1.234 · Max")
    }

    func testSignedOutSaysHowToSignIn() {
        XCTAssertEqual(
            claudeCodeAuthProbe(#"{"loggedIn": false}"#),
            .refused(
                "Claude Code isn't signed in. Open Terminal, run `claude` and sign in with `/login`."
            )
        )
    }

    func testUnreadableIsNotReportedAsSignedOut() {
        // Two different repairs. Telling someone to sign in when they already
        // are sends them somewhere that cannot fix it.
        XCTAssertEqual(
            claudeCodeAuthProbe("command not found"),
            .refused("Couldn't read the sign-in status from Claude Code.")
        )
    }

    func testAReplyWithNoPlanStillCounts() {
        XCTAssertEqual(claudeCodeAuthProbe(#"{"loggedIn": true}"#), .signedIn(detail: ""))
        XCTAssertEqual(planLabel(nil), "")
        XCTAssertEqual(planLabel("  "), "")
        XCTAssertEqual(planLabel("pro"), "Pro")
    }
}
