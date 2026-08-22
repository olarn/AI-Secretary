import XCTest
@testable import SecretaryCore

final class AppVersionTests: XCTestCase {
    func testItReadsAsDottedNumbers() {
        XCTAssertEqual(AppVersion(major: 1, minor: 2, patch: 3).description, "1.2.3")
    }

    func testItOrdersByNumberSoTenSortsAboveNineRatherThanBelowItAsText() {
        XCTAssertLessThan(AppVersion(major: 0, minor: 9, patch: 9), AppVersion(major: 0, minor: 10, patch: 0))
        XCTAssertLessThan(AppVersion(major: 0, minor: 5, patch: 0), AppVersion(major: 1, minor: 0, patch: 0))
        XCTAssertLessThan(AppVersion(major: 1, minor: 0, patch: 1), AppVersion(major: 1, minor: 1, patch: 0))
    }

    func testTheCurrentVersionIsARealVersion() {
        let current = AppVersion.current
        XCTAssertGreaterThan(current, AppVersion(major: 0, minor: 0, patch: 0))
        XCTAssertEqual(AppInfo.version, current)
    }

    func testTheVersionStringIsThreeNumbersBecauseThePackagingScriptGrepsForThatShape() {
        let parts = AppVersion.current.description.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil }, "Every part has to be a number")
    }

    func testTheStatusMenuHeaderIsNameAndVersionAndDeliberatelyNotTheCommit() {
        XCTAssertEqual(AppInfo.statusMenuHeader, "AI Secretary \(AppVersion.current)")
        XCTAssertFalse(AppInfo.statusMenuHeader.contains("("))
    }
}
