import XCTest
@testable import SecretaryCore

/// Every place the version is written must agree with the code.
///
/// `AppVersion.current` is the single source, and the About window and the
/// packaging script both read it — but prose can't. The root README states the
/// version in words, which is a second copy, and a second copy of a number is a
/// number that goes stale. Rather than trusting whoever bumps it to remember
/// the README, the disagreement fails here.
///
/// Add a row to `versionMentions` whenever another document starts quoting the
/// version.
final class VersionInSyncTests: XCTestCase {
    /// Files that state the version, and the pattern that finds it.
    private let versionMentions: [(path: String, pattern: String)] = [
        ("README.md", #"Version (\d+\.\d+\.\d+)"#)
    ]

    /// The repository root, found by walking up from this file rather than from
    /// the working directory, which differs between `swift test` and Xcode.
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)          // …/code/Tests/SecretaryCoreTests/ThisFile.swift
            .deletingLastPathComponent()         // …/code/Tests/SecretaryCoreTests
            .deletingLastPathComponent()         // …/code/Tests
            .deletingLastPathComponent()         // …/code
            .deletingLastPathComponent()         // repository root
    }

    func testEveryDocumentedVersionMatchesTheCode() throws {
        let expected = AppVersion.current.description

        for mention in versionMentions {
            let url = repositoryRoot.appendingPathComponent(mention.path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                // A worktree may not carry every document; a missing file is
                // not a stale one.
                continue
            }
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

    /// The packaging script parses the declaration with `sed`, so its exact
    /// shape is load-bearing: reformatted onto several lines, the bundle would
    /// silently carry no version at all.
    func testTheVersionDeclarationStaysOnOneLineForTheScript() throws {
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
