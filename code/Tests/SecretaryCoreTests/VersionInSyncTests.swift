import XCTest
@testable import SecretaryCore

final class VersionInSyncTests: XCTestCase {
    private let documentsQuotingTheVersion: [(path: String, pattern: String)] = [
        ("README.md", #"Version (\d+\.\d+\.\d+)"#),
        ("docs/FEATURES.md", #"State of the product at v(\d+\.\d+\.\d+)"#)
    ]

    private var repositoryRoot: URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testTarget = thisFile.deletingLastPathComponent()
        let testsDirectory = testTarget.deletingLastPathComponent()
        let codeDirectory = testsDirectory.deletingLastPathComponent()
        return codeDirectory.deletingLastPathComponent()
    }

    private func textIfTheFileIsPresent(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    func testEveryDocumentQuotingTheVersionAgreesWithTheCode() throws {
        let expected = AppVersion.current.description

        for mention in documentsQuotingTheVersion {
            let url = repositoryRoot.appendingPathComponent(mention.path)
            guard let text = textIfTheFileIsPresent(at: url) else { continue }
            let regex = try NSRegularExpression(pattern: mention.pattern)
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            XCTAssertFalse(
                matches.isEmpty,
                "\(mention.path) no longer states a version — either restore it or drop the row"
            )
            for match in matches {
                guard let found = Range(match.range(at: 1), in: text) else { continue }
                XCTAssertEqual(
                    String(text[found]),
                    expected,
                    "\(mention.path) says \(text[found]) but AppVersion.current is \(expected)"
                )
            }
        }
    }

    func testTheVersionDeclarationStaysOnOneLineOrThePackagedBundleCarriesNoVersion() throws {
        let source = repositoryRoot
            .appendingPathComponent("code/Sources/SecretaryCore/AppVersion.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let pattern = #"AppVersion\(major: \d+, minor: \d+, patch: \d+\)"#
        XCTAssertNotNil(
            text.range(of: pattern, options: .regularExpression),
            "package-app.sh parses this exact shape on one line"
        )
    }
}
