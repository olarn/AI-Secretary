import XCTest
@testable import LLMProvider

final class ClaudeCodeFailureTests: XCTestCase {
    func testALoginPromptIsNotBeingSignedIn() {
        XCTAssertEqual(
            ClaudeCodeFailure.classify("Invalid API key · Please run /login"),
            .notSignedIn
        )
        XCTAssertEqual(
            ClaudeCodeFailure.classify("OAuth token has expired"),
            .notSignedIn
        )
    }

    func testAUsageLimitIsRecognised() {
        XCTAssertEqual(
            ClaudeCodeFailure.classify("Claude usage limit reached. Your limit will reset at 3pm"),
            .usageLimitReached
        )
        XCTAssertEqual(ClaudeCodeFailure.classify("API Error: 429 rate_limit_error"), .usageLimitReached)
    }

    func testANetworkFailureIsRecognised() {
        XCTAssertEqual(ClaudeCodeFailure.classify("Connection error: getaddrinfo ENOTFOUND api.anthropic.com"), .offline)
        XCTAssertEqual(ClaudeCodeFailure.classify("fetch failed"), .offline)
    }

    func testAProcessThatWouldNotStart() {
        XCTAssertEqual(
            ClaudeCodeFailure.classify("The file “claude” doesn’t exist. No such file or directory"),
            .couldNotStart
        )
    }

    func testASilentExitCarriesItsCode() {
        XCTAssertEqual(ClaudeCodeFailure.classify("exited with code 137"), .silentExit(code: 137))
    }

    func testAnythingElseStaysUnknown() {
        XCTAssertEqual(ClaudeCodeFailure.classify("TypeError: undefined is not a function"), .unknown)
    }

    func testEveryKnownCauseNamesClaudeCodeAndSaysItCannotBeReached() {
        let causes: [ClaudeCodeFailure] = [
            .notSignedIn, .usageLimitReached, .offline, .couldNotStart, .silentExit(code: 1)
        ]
        for cause in causes {
            let message = cause.message(detail: "raw text")
            XCTAssertTrue(message.hasPrefix("Can't reach Claude Code"), "\(cause): \(message)")
        }
    }

    func testTheOriginalTextIsKeptUnderTheExplanation() {
        let message = ClaudeCodeFailure.notSignedIn.message(detail: "Invalid API key · Please run /login")
        XCTAssertTrue(message.contains("Invalid API key · Please run /login"), message)
        XCTAssertTrue(message.contains("/login"), message)
    }

    func testNothingIsQuotedWhenThereIsNothingToQuote() {
        XCTAssertFalse(ClaudeCodeFailure.unknown.message(detail: "   ").contains("```"))
        XCTAssertFalse(ClaudeCodeFailure.silentExit(code: 2).message(detail: "exited with code 2").contains("```"))
    }

    func testTheChatErrorItselfExplainsTheCause() {
        let described = ChatError.claudeCodeFailed("Claude usage limit reached").errorDescription ?? ""
        XCTAssertTrue(described.hasPrefix("Can't reach Claude Code"), described)
        XCTAssertTrue(described.contains("usage limit"), described)
    }
}
