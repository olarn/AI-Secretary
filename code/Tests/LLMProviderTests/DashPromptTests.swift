import FunctionalCore
import XCTest
@testable import LLMProvider

/// A message must never be mistaken for a command-line flag.
///
/// Reported from use: a reply that began "- A" came back as
/// `error: unknown option '- A…'`. Passed as the value of `-p`, a message
/// starting with a dash was read as an option, so bullet lists — and any
/// question about a flag — were unsendable. The fix at the time was to put the
/// message last, behind `--`.
///
/// Since the move to `--input-format stream-json` the message is not on the
/// command line at all: it goes down stdin as a JSON string, which nothing
/// parses as a flag. That retires the hazard rather than guarding it, so these
/// tests now assert the two things that make that true — the message travels
/// intact, and it never reaches the argument list.
final class DashPromptTests: XCTestCase {
    private func launchArguments() -> [String] {
        ClaudeCodeProvider.launchArguments(
            model: .none(),
            effort: .none(),
            system: .some("be brief"),
            resume: "abc123",
            configuration: .init(browserEnabled: true)
        )
    }

    private func sentText(_ prompt: String) -> String? {
        guard let line = warmTurnInputLine(prompt: prompt),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else { return nil }
        return content.first?["text"] as? String
    }

    /// The exact message that failed.
    func testTheMessageThatUsedToBeReadAsAFlagTravelsIntact() {
        let prompt = "- A\n- เอา get current date ก่อน 1 API"

        XCTAssertEqual(sentText(prompt), prompt)
        XCTAssertFalse(launchArguments().contains(prompt))
    }

    func testEveryShapeThatLooksLikeAFlagSurvives() {
        for prompt in ["--", "-p", "--resume evil", "-", "--append-system-prompt x"] {
            XCTAssertEqual(sentText(prompt), prompt, "Mangled: \(prompt)")
        }
    }

    /// Newlines are the reason this is one JSON line rather than raw text: the
    /// newline is what tells the CLI the message is over, so a message
    /// containing them must not end it early.
    func testAMessageWithNewlinesIsStillOneLine() {
        guard let line = warmTurnInputLine(prompt: "first\nsecond\nthird") else {
            return XCTFail("Expected a line")
        }

        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1)
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertEqual(sentText("first\nsecond\nthird"), "first\nsecond\nthird")
    }

    /// No prompt on the command line at all, whatever it says.
    func testTheCommandLineCarriesNoMessage() {
        let args = launchArguments()

        XCTAssertEqual(args.last, "-p")
        XCTAssertFalse(args.contains("--"))
        XCTAssertTrue(args.contains("--input-format"))
    }
}
