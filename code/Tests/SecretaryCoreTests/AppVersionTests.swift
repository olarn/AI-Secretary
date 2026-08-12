import XCTest
@testable import SecretaryCore

final class AppVersionTests: XCTestCase {
    func testItReadsAsDottedNumbers() {
        XCTAssertEqual(AppVersion(major: 1, minor: 2, patch: 3).description, "1.2.3")
    }

    /// Versions are numbers, not text: sorted as strings, "0.10.0" would come
    /// before "0.9.9".
    func testItOrdersByNumberNotByText() {
        XCTAssertLessThan(AppVersion(major: 0, minor: 9, patch: 9), AppVersion(major: 0, minor: 10, patch: 0))
        XCTAssertLessThan(AppVersion(major: 0, minor: 5, patch: 0), AppVersion(major: 1, minor: 0, patch: 0))
        XCTAssertLessThan(AppVersion(major: 1, minor: 0, patch: 1), AppVersion(major: 1, minor: 1, patch: 0))
    }

    func testTheCurrentVersionIsARealVersion() {
        let current = AppVersion.current
        XCTAssertGreaterThan(current, AppVersion(major: 0, minor: 0, patch: 0))
        XCTAssertEqual(AppInfo.version, current)
    }

    /// The packaging script parses the `AppVersion.current` literal to fill in
    /// `CFBundleShortVersionString`, so the shape it greps for has to keep
    /// producing three dot-separated numbers.
    func testTheVersionStringIsThreeNumbers() {
        let parts = AppVersion.current.description.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil }, "Every part has to be a number")
    }

    /// Name and version, and deliberately not the commit.
    ///
    /// This assertion has always read this way and always passed, but for the
    /// wrong reason: `AppInfo.build` comes from the bundle's Info.plist, which
    /// is absent under `swift test`, so the branch that appended `(sha)` was
    /// never once executed here. It described the test rig rather than the app.
    /// Now it describes both.
    func testTheAppAnswersWithItsNameAndVersionAndNoCommit() {
        XCTAssertEqual(AppInfo.summary, "AI Secretary \(AppVersion.current)")
        XCTAssertFalse(AppInfo.summary.contains("("))
    }
}
