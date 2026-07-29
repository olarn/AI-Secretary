import FunctionalCore
import XCTest
@testable import LLMProvider

/// A message must never be mistaken for a command-line flag.
///
/// Reported from use: a reply that began "- A" came back as
/// `error: unknown option '- A…'`. Passed as the value of `-p`, a message
/// starting with a dash is read as an option, so bullet lists — and any
/// question about a flag — were unsendable. Confirmed against the real CLI
/// that moving it behind `--` sends it verbatim.
final class DashPromptTests: XCTestCase {
    private func arguments(_ prompt: String) -> [String] {
        ClaudeCodeProvider.arguments(
            prompt: prompt,
            model: .none(),
            effort: .none(),
            system: .some("be brief"),
            resume: "abc123",
            configuration: .init(browserEnabled: true)
        )
    }

    /// The exact message that failed.
    func testAMessageStartingWithADashIsNotReadAsAFlag() {
        let prompt = "- A\n- เอา get current date ก่อน 1 API"
        let args = arguments(prompt)
        guard let separator = args.firstIndex(of: "--") else {
            return XCTFail("Expected a -- separator. Got: \(args)")
        }
        XCTAssertEqual(args[separator - 1], "-p")
        XCTAssertEqual(args.last, prompt)
    }

    /// Everything after `--` is positional, so the message has to be the last
    /// argument. A flag appended later would be swallowed into the prompt.
    func testNothingFollowsTheMessage() {
        let args = arguments("hello")
        XCTAssertEqual(args.last, "hello")
        XCTAssertEqual(args.firstIndex(of: "--"), args.count - 2)
    }

    /// The separator must appear once. A message that is literally "--" is a
    /// positional after the real separator, not a second one.
    func testAMessageThatIsJustDashesIsStillTheMessage() {
        let args = arguments("--")
        XCTAssertEqual(args.last, "--")
        XCTAssertEqual(args.filter { $0 == "--" }.count, 2)
        XCTAssertEqual(args[args.count - 3], "-p")
    }

    /// The other flags must still be there, and still ahead of the separator,
    /// or they would be read as part of the message.
    func testTheFlagsStillPrecedeTheMessage() {
        let args = arguments("hi")
        let separator = args.firstIndex(of: "--") ?? args.count
        for flag in ["--output-format", "--permission-mode", "--chrome", "--resume", "--append-system-prompt"] {
            guard let at = args.firstIndex(of: flag) else {
                return XCTFail("\(flag) went missing. Got: \(args)")
            }
            XCTAssertLessThan(at, separator, "\(flag) must come before --")
        }
    }

    func testAnOrdinaryMessageIsUnaffected() {
        XCTAssertEqual(arguments("what changed today?").last, "what changed today?")
    }
}
