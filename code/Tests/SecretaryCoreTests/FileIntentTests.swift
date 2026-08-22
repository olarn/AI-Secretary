import FunctionalCore
import XCTest
import ToolAdapters
@testable import SecretaryCore

final class FileIntentTests: XCTestCase {
    private let classifier = RuleBasedIntentClassifier()

    func testReadWithPathAndProject() {
        XCTAssertEqual(
            classifier.classify("read README.md in AI-Secretary"),
            .fileTool(operation: .readFile(relativePath: "README.md"), projectQuery: .some("AI-Secretary"))
        )
    }

    func testListWithNoPathDefaultsToRoot() {
        XCTAssertEqual(
            classifier.classify("list in AI-Secretary"),
            .fileTool(operation: .listDirectory(relativePath: "."), projectQuery: .some("AI-Secretary"))
        )
    }

    func testListWithSubdirectory() {
        XCTAssertEqual(
            classifier.classify("list src/models in Demo"),
            .fileTool(operation: .listDirectory(relativePath: "src/models"), projectQuery: .some("Demo"))
        )
    }

    func testDotfilePathKeepsLeadingDot() {
        XCTAssertEqual(
            classifier.classify("read .env in Demo"),
            .fileTool(operation: .readFile(relativePath: ".env"), projectQuery: .some("Demo"))
        )
    }

    func testBareListWithNoProject() {
        XCTAssertEqual(
            classifier.classify("ls"),
            .fileTool(operation: .listDirectory(relativePath: "."), projectQuery: Option.none())
        )
    }

    func testReadWithoutAPathIsNotAFileOp() {
        if case .fileTool = classifier.classify("read") {
            XCTFail("bare 'read' should not classify as a file op")
        }
    }

    func testGitStatusStillClassifiesAsGit() {
        XCTAssertEqual(
            classifier.classify("status in Demo"),
            .codeTool(operation: .status, projectQuery: .some("demo"))
        )
    }

    func testWeakVerbWithProseIsChatNotAFileOp() {
        for prose in ["read me a poem", "list your capabilities", "cat got my tongue"] {
            if case .fileTool = classifier.classify(prose) {
                XCTFail("\"\(prose)\" should stay a conversation, not a file op")
            }
        }
    }

    func testWeakVerbWithPathLikeArgIsAFileOpWithoutProject() {
        XCTAssertEqual(
            classifier.classify("read README.md"),
            .fileTool(operation: .readFile(relativePath: "README.md"), projectQuery: Option.none())
        )
    }

    func testExplicitPhrasingIsAFileOpEvenWithoutPathOrProject() {
        XCTAssertEqual(
            classifier.classify("show file notes"),
            .fileTool(operation: .readFile(relativePath: "notes"), projectQuery: Option.none())
        )
    }

    func testReadTheLogFileIsAFileOpNotGitLog() {
        XCTAssertEqual(
            classifier.classify("read the-log-file.txt in Demo"),
            .fileTool(operation: .readFile(relativePath: "the-log-file.txt"), projectQuery: .some("Demo"))
        )
    }
}

final class NonASCIIIntentTests: XCTestCase {
    private let classifier = RuleBasedIntentClassifier()

    func testThaiMessageContainingAnEnglishMarkerDoesNotCrash() {
        let intent = classifier.classify("หาราคาเฉลี่ย รองเท้า On Cloud ในไทย")
        guard case .unknown = intent else {
            return XCTFail("A question about shoe prices is conversation, got: \(intent)")
        }
    }

    func testAssortedNonASCIIMessagesAreClassifiedWithoutCrashing() {
        let messages = [
            "สรุปโปรเจกต์นี้ให้หน่อย",
            "ราคา On Cloud ในไทยเท่าไหร่",
            "เปรียบเทียบ A กับ B for ฉันหน่อย",
            "日本語のテキスト in プロジェクト",
            "café on the corner",
            "🎉 in 🎊",
            " on ",
            "on"
        ]
        for message in messages {
            _ = classifier.classify(message)
        }
    }

    func testUppercaseMarkerStillSelectsTheProject() {
        guard case .fileTool(_, let query) = classifier.classify("read notes.md IN Fixture") else {
            return XCTFail("Expected a file operation")
        }
        XCTAssertEqual(query, .some("Fixture"))
    }

    func testAThaiProjectNameSurvivesTheSplit() {
        guard case .fileTool(let operation, let query) = classifier.classify("read about.md in โลหะเจริญ") else {
            return XCTFail("Expected a file operation")
        }
        XCTAssertEqual(operation.relativePath, "about.md")
        XCTAssertEqual(query, .some("โลหะเจริญ"))
    }
}
