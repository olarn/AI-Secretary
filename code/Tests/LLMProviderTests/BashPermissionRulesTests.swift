import XCTest
@testable import LLMProvider

/// What a refused `Bash` call has to be granted before it will actually run.
///
/// Every case here is one the owner hit: approving the offer and being blocked
/// again, with the same card, on the same command. The rules looked plausible
/// in the offer — which is why nobody suspected them — and authorised nothing.
///
/// The expectations were checked against Claude Code 2.1.229 rather than
/// reasoned from the docs, because the docs do not mention that a `&&` chain
/// needs a rule per operation. Its refusal does: "This Bash command contains
/// multiple operations. The following parts require approval: …".
final class BashPermissionRulesTests: XCTestCase {
    func testASimpleCommandIsNarrowedToItsFirstTwoWords() {
        XCTAssertEqual(
            bashPermissionRules(for: "npm test --watch=false"),
            ["Bash(npm test *)"]
        )
    }

    /// The first half of the bug. A path with a space in it was cut in the
    /// middle, and the rule carried an unterminated quote — so it matched
    /// nothing at all, and the command it was granted for stayed refused.
    func testAQuotedPathIsKeptWholeRatherThanCutAtItsFirstSpace() {
        let rules = bashPermissionRules(
            for: #"python3 "/Users/o/1-Projects/TISCO - AI Sharing/build_deck.py""#
        )

        XCTAssertEqual(rules, [#"Bash(python3 "/Users/o/1-Projects/TISCO - AI Sharing/build_deck.py" *)"#])
    }

    /// The second half, and the one that made approving useless: Claude Code
    /// requires *every* operation in the line to be permitted. One rule for the
    /// head of the command left the rest refused.
    func testEveryOperationInAChainGetsItsOwnRule() {
        let rules = bashPermissionRules(
            for: #"cd "/Users/o/TISCO - AI Sharing" && python3 -c "import pptx" || pip3 install python-pptx"#
        )

        XCTAssertEqual(rules, [
            #"Bash(cd "/Users/o/TISCO - AI Sharing" *)"#,
            "Bash(python3 -c *)",
            "Bash(pip3 install *)",
        ])
    }

    func testPipesAndSemicolonsSplitTheSameWay() {
        XCTAssertEqual(
            bashPermissionRules(for: "cat notes.md | grep TODO ; wc -l notes.md"),
            ["Bash(cat notes.md *)", "Bash(grep TODO *)", "Bash(wc -l *)"]
        )
    }

    /// An operator inside quotes is an argument, not an operator. Splitting
    /// there would produce rules for fragments that are not commands, and the
    /// real command would still be refused.
    func testAnOperatorInsideQuotesIsNotASplit() {
        XCTAssertEqual(
            bashPermissionRules(for: #"grep "a && b" notes.md"#),
            [#"Bash(grep "a && b" *)"#]
        )
    }

    /// A redirect is part of its command rather than a new one — this is the
    /// exact tail of the command the owner ran.
    func testARedirectStaysWithItsCommand() {
        XCTAssertEqual(
            bashPermissionRules(for: "python3 -c \"import pptx\" 2>&1"),
            ["Bash(python3 -c *)"]
        )
    }

    func testTheSameRuleIsNotAskedForTwice() {
        XCTAssertEqual(
            bashPermissionRules(for: "python3 a.py && python3 b.py"),
            ["Bash(python3 a.py *)", "Bash(python3 b.py *)"]
        )
        XCTAssertEqual(
            bashPermissionRules(for: "make build && make build"),
            ["Bash(make build *)"]
        )
    }

    func testAOneWordCommandIsItsOwnPrefix() {
        XCTAssertEqual(bashPermissionRules(for: "pwd"), ["Bash(pwd *)"])
    }

    func testNothingToRunAsksForNothing() {
        XCTAssertEqual(bashPermissionRules(for: "   "), [])
        XCTAssertEqual(bashPermissionRules(for: "&&"), [])
    }
}
