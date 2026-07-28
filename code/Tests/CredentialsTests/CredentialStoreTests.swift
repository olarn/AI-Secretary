import FunctionalCore
import XCTest
@testable import Credentials

final class InMemoryCredentialStoreTests: XCTestCase {
    func testStoresAndReturnsKey() {
        let store = InMemoryCredentialStore()
        XCTAssertEqual(store.apiKey(), Option.none())
        XCTAssertFalse(store.hasAPIKey)

        XCTAssertTrue(store.setAPIKey(.some("sk-ant-test")).isRight)
        XCTAssertEqual(store.apiKey(), .some("sk-ant-test"))
        XCTAssertTrue(store.hasAPIKey)
    }

    func testClearingRemovesKey() {
        let store = InMemoryCredentialStore(apiKey: .some("sk-ant-test"))
        XCTAssertTrue(store.setAPIKey(.none()).isRight)
        XCTAssertEqual(store.apiKey(), Option.none())
        XCTAssertFalse(store.hasAPIKey)
    }

    func testEmptyStringIsTreatedAsNoKey() {
        let store = InMemoryCredentialStore()
        store.setAPIKey(.some(""))
        XCTAssertEqual(store.apiKey(), Option.none())
        XCTAssertFalse(store.hasAPIKey)
    }

    /// The view edge hands over raw text; blank or whitespace-only means "no
    /// key", so a user clearing the field doesn't store a space.
    func testTextConvenienceTrimsAndTreatsBlankAsAbsent() {
        let store = InMemoryCredentialStore()

        store.setAPIKey(text: "  sk-ant-padded  ")
        XCTAssertEqual(store.apiKey(), .some("sk-ant-padded"))

        store.setAPIKey(text: "   ")
        XCTAssertEqual(store.apiKey(), Option.none())
    }
}

final class NonEmptyTests: XCTestCase {
    func testBlankInputIsAbsent() {
        XCTAssertEqual(nonEmpty(""), Option.none())
        XCTAssertEqual(nonEmpty("  \n "), Option.none())
    }

    func testTrimmedContentIsPresent() {
        XCTAssertEqual(nonEmpty(" hello "), .some("hello"))
    }
}
