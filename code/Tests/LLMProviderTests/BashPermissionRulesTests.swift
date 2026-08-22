import XCTest
@testable import LLMProvider

final class BashPermissionRulesTests: XCTestCase {
    func testASimpleCommandIsNarrowedToItsFirstTwoWords() {
        XCTAssertEqual(
            bashPermissionRules(for: "npm test --watch=false"),
            ["Bash(npm test *)"]
        )
    }

    func testAQuotedPathIsKeptWholeRatherThanCutAtItsFirstSpace() {
        let rules = bashPermissionRules(
            for: #"python3 "/Users/o/1-Projects/TISCO - AI Sharing/build_deck.py""#
        )

        XCTAssertEqual(rules, [#"Bash(python3 "/Users/o/1-Projects/TISCO - AI Sharing/build_deck.py" *)"#])
    }

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

    func testAnOperatorInsideQuotesIsNotASplit() {
        XCTAssertEqual(
            bashPermissionRules(for: #"grep "a && b" notes.md"#),
            [#"Bash(grep "a && b" *)"#]
        )
    }

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
