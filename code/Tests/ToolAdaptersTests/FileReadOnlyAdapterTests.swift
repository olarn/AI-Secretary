import FunctionalCore
import XCTest
import ProjectRegistry
@testable import ToolAdapters

final class FileReadOnlyAdapterTests: XCTestCase {
    private var root: URL!
    private var outside: URL!
    private let adapter = FileReadOnlyAdapter(maxFileBytes: 64)

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("file-fixture-\(UUID().uuidString)")
        root = base.appendingPathComponent("project")
        outside = base.appendingPathComponent("secret")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        try "hello\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "int main(){}\n".write(to: root.appendingPathComponent("src/main.c"), atomically: true, encoding: .utf8)
        try "top secret\n".write(to: outside.appendingPathComponent("passwords.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        if let base = root?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    private func project() -> Project {
        Project(name: "Fixture", path: root.path, allowedTools: [FileReadOnlyAdapter.toolIdentifier])
    }

    func testListsRootSortedWithDirectoriesMarked() throws {
        let result = try expectSuccess(adapter.run(.listDirectory(relativePath: "."), in: project()))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "README.md\nsrc/")
    }

    func testListsSubdirectory() throws {
        let result = try expectSuccess(adapter.run(.listDirectory(relativePath: "src"), in: project()))
        XCTAssertEqual(result.output, "main.c")
    }

    func testReadsTextFile() throws {
        let result = try expectSuccess(adapter.run(.readFile(relativePath: "README.md"), in: project()))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "hello\n")
    }

    func testDotdotEscapeIsRefused() throws {
        XCTAssertEqual(try expectRefusal(adapter.run(.readFile(relativePath: "../secret/passwords.txt"), in: project())), .pathEscapesProject("../secret/passwords.txt"))
    }

    func testAbsolutePathIsRefused() throws {
        let abs = outside.appendingPathComponent("passwords.txt").path
        XCTAssertEqual(try expectRefusal(adapter.run(.readFile(relativePath: abs), in: project())), .pathEscapesProject(abs))
    }

    func testSymlinkPointingOutsideIsRefused() throws {
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertEqual(try expectRefusal(adapter.run(.readFile(relativePath: "escape/passwords.txt"), in: project())), .pathEscapesProject("escape/passwords.txt"))
    }

    func testMissingFileReported() throws {
        let error = try expectRefusal(adapter.run(.readFile(relativePath: "nope.txt"), in: project()))
        guard case ToolError.fileNotFound = error else { return XCTFail("expected fileNotFound, got \(error)") }
    }

    func testFileExceedingLimitIsRefused() throws {
        let big = String(repeating: "x", count: 200)
        try big.write(to: root.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
        let error = try expectRefusal(adapter.run(.readFile(relativePath: "big.txt"), in: project()))
        guard case ToolError.fileTooLarge = error else { return XCTFail("expected fileTooLarge, got \(error)") }
    }

    func testReadingADirectoryAsFileIsRefused() throws {
        let error = try expectRefusal(adapter.run(.readFile(relativePath: "src"), in: project()))
        guard case ToolError.notAFile = error else { return XCTFail("expected notAFile, got \(error)") }
    }
}
