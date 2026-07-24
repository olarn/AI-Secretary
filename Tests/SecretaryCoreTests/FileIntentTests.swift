import XCTest
import ToolAdapters
@testable import SecretaryCore

final class FileIntentTests: XCTestCase {
    private let classifier = RuleBasedIntentClassifier()

    func testReadWithPathAndProject() {
        XCTAssertEqual(
            classifier.classify("read README.md in AI-Secretary"),
            .fileTool(operation: .readFile(relativePath: "README.md"), projectQuery: "AI-Secretary")
        )
    }

    func testListWithNoPathDefaultsToRoot() {
        XCTAssertEqual(
            classifier.classify("list in AI-Secretary"),
            .fileTool(operation: .listDirectory(relativePath: "."), projectQuery: "AI-Secretary")
        )
    }

    func testListWithSubdirectory() {
        XCTAssertEqual(
            classifier.classify("list src/models in Demo"),
            .fileTool(operation: .listDirectory(relativePath: "src/models"), projectQuery: "Demo")
        )
    }

    func testDotfilePathKeepsLeadingDot() {
        XCTAssertEqual(
            classifier.classify("read .env in Demo"),
            .fileTool(operation: .readFile(relativePath: ".env"), projectQuery: "Demo")
        )
    }

    func testBareListWithNoProject() {
        XCTAssertEqual(
            classifier.classify("ls"),
            .fileTool(operation: .listDirectory(relativePath: "."), projectQuery: nil)
        )
    }

    func testReadWithoutAPathIsNotAFileOp() {
        // "read" alone shouldn't become a file op with an empty path.
        if case .fileTool = classifier.classify("read") {
            XCTFail("bare 'read' should not classify as a file op")
        }
    }

    func testGitStatusStillClassifiesAsGit() {
        XCTAssertEqual(
            classifier.classify("status in Demo"),
            .codeTool(operation: .status, projectQuery: "demo")
        )
    }

    func testWeakVerbWithProseIsChatNotAFileOp() {
        // "read"/"list" are common chat openers; without a project scope or a
        // path-like argument they must not hijack the conversation.
        for prose in ["read me a poem", "list your capabilities", "cat got my tongue"] {
            if case .fileTool = classifier.classify(prose) {
                XCTFail("\"\(prose)\" should stay a conversation, not a file op")
            }
        }
    }

    func testWeakVerbWithPathLikeArgIsAFileOpWithoutProject() {
        XCTAssertEqual(
            classifier.classify("read README.md"),
            .fileTool(operation: .readFile(relativePath: "README.md"), projectQuery: nil)
        )
    }

    func testExplicitPhrasingIsAFileOpEvenWithoutPathOrProject() {
        XCTAssertEqual(
            classifier.classify("show file notes"),
            .fileTool(operation: .readFile(relativePath: "notes"), projectQuery: nil)
        )
    }

    func testReadTheLogFileIsAFileOpNotGitLog() {
        // The word "log" must not hijack a file read.
        XCTAssertEqual(
            classifier.classify("read the-log-file.txt in Demo"),
            .fileTool(operation: .readFile(relativePath: "the-log-file.txt"), projectQuery: "Demo")
        )
    }
}
