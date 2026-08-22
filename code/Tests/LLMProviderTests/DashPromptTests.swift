import FunctionalCore
import XCTest
@testable import LLMProvider

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

    func testAMessageWithNewlinesIsStillOneLine() {
        guard let line = warmTurnInputLine(prompt: "first\nsecond\nthird") else {
            return XCTFail("Expected a line")
        }

        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1)
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertEqual(sentText("first\nsecond\nthird"), "first\nsecond\nthird")
    }

    func testTheCommandLineCarriesNoMessage() {
        let args = launchArguments()

        XCTAssertEqual(args.last, "-p")
        XCTAssertFalse(args.contains("--"))
        XCTAssertTrue(args.contains("--input-format"))
    }
}
