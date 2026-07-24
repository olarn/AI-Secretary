import XCTest
@testable import Credentials

final class InMemoryCredentialStoreTests: XCTestCase {
    func testStoresAndReturnsKey() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(store.apiKey())
        XCTAssertFalse(store.hasAPIKey)

        try store.setAPIKey("sk-ant-test")
        XCTAssertEqual(store.apiKey(), "sk-ant-test")
        XCTAssertTrue(store.hasAPIKey)
    }

    func testClearingRemovesKey() throws {
        let store = InMemoryCredentialStore(apiKey: "sk-ant-test")
        try store.setAPIKey(nil)
        XCTAssertNil(store.apiKey())
        XCTAssertFalse(store.hasAPIKey)
    }

    func testEmptyStringIsTreatedAsNoKey() throws {
        let store = InMemoryCredentialStore()
        try store.setAPIKey("")
        XCTAssertNil(store.apiKey())
        XCTAssertFalse(store.hasAPIKey)
    }
}
