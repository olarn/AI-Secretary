import XCTest
import FunctionalCore
import LLMProvider
@testable import SecretaryCore

final class VendorChoiceStoreTests: XCTestCase {
    private func store(_ character: UUID = UUID()) -> (UserDefaultsVendorChoiceStore, UserDefaults) {
        let name = "VendorChoiceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (UserDefaultsVendorChoiceStore(character: character, defaults: defaults), defaults)
    }

    func testAFreshCharacterWorksThroughClaudeCode() {
        let (subject, _) = store()
        XCTAssertEqual(subject.load(), .claudeCode)
    }

    func testTheMakerAndItsPathComeBack() {
        let (subject, _) = store()
        subject.save(VendorChoice(vendorID: "opencode", cliPath: .some("/opt/homebrew/bin/opencode")))
        XCTAssertEqual(
            subject.load(),
            VendorChoice(vendorID: "opencode", cliPath: .some("/opt/homebrew/bin/opencode"))
        )
    }

    func testTwoCharactersDoNotShareAMaker() {
        let name = "VendorChoiceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let miku = UserDefaultsVendorChoiceStore(character: UUID(), defaults: defaults)
        let anya = UserDefaultsVendorChoiceStore(character: UUID(), defaults: defaults)

        miku.save(VendorChoice(vendorID: "opencode"))

        XCTAssertEqual(miku.load().vendorID, "opencode")
        XCTAssertEqual(anya.load(), .claudeCode)
    }

    func testClearingThePathRemovesItRatherThanStoringABlank() {
        let (subject, defaults) = store()
        subject.save(VendorChoice(vendorID: "opencode", cliPath: .some("/tmp/opencode")))
        subject.save(VendorChoice(vendorID: "opencode", cliPath: .none()))

        XCTAssertEqual(subject.load().cliPath, Option.none())
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { $0.hasSuffix(".cliPath") })
    }

    func testAWhitespacePathIsTheSameAsNoPath() {
        let (subject, _) = store()
        subject.save(VendorChoice(vendorID: "opencode", cliPath: .some("   ")))
        XCTAssertEqual(subject.load().cliPath, Option.none())
    }

    func testAMakerThisBuildHasNeverHeardOfReadsAsTheDefault() {
        let (subject, _) = store()
        subject.save(VendorChoice(vendorID: "gemini-cli"))
        XCTAssertEqual(subject.load().vendorID, AIVendor.claudeCode.id)
    }

    func testChangingOneHalfKeepsTheOther() {
        let choice = VendorChoice(vendorID: "opencode", cliPath: .some("/tmp/oc"))
        XCTAssertEqual(choice.choosing(vendorID: "claude-code").cliPath, Option.some("/tmp/oc"))
        XCTAssertEqual(choice.choosing(cliPath: .none()).vendorID, "opencode")
    }
}
