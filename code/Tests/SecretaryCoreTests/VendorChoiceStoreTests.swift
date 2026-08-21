import XCTest
import FunctionalCore
import LLMProvider
@testable import SecretaryCore

/// Remembering which maker a character works through.
final class VendorChoiceStoreTests: XCTestCase {
    private func store(_ character: UUID = UUID()) -> (UserDefaultsVendorChoiceStore, UserDefaults) {
        // A suite of its own, so a test can never write into the person's real
        // preferences — the same reason the in-memory store is the default.
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
        // The whole reason this is keyed by profile: one on the subscription,
        // one on a local model, on the same desktop.
        let name = "VendorChoiceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let miku = UserDefaultsVendorChoiceStore(character: UUID(), defaults: defaults)
        let anya = UserDefaultsVendorChoiceStore(character: UUID(), defaults: defaults)

        miku.save(VendorChoice(vendorID: "opencode"))

        XCTAssertEqual(miku.load().vendorID, "opencode")
        XCTAssertEqual(anya.load(), .claudeCode)
    }

    func testClearingThePathRemovesItRatherThanStoringABlank() {
        // "Look in the usual places" is a choice. An empty string stored here
        // would later read as a path that happens to be blank.
        let (subject, defaults) = store()
        subject.save(VendorChoice(vendorID: "opencode", cliPath: .some("/tmp/opencode")))
        subject.save(VendorChoice(vendorID: "opencode", cliPath: .none()))

        XCTAssertEqual(subject.load().cliPath, Option.none())
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { $0.hasSuffix(".cliPath") })
    }

    func testAWhitespacePathIsTheSameAsNoPath() {
        // A field the user cleared, not a path made of spaces.
        let (subject, _) = store()
        subject.save(VendorChoice(vendorID: "opencode", cliPath: .some("   ")))
        XCTAssertEqual(subject.load().cliPath, Option.none())
    }

    func testAMakerThisBuildHasNeverHeardOfReadsAsTheDefault() {
        // A settings file written by a later build must not leave a character
        // unable to work at all.
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
