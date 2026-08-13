import XCTest
@testable import SecretaryCore

/// Where each character's look is kept, and what she reads before she has one.
///
/// The fallback is the whole reason this is not a rename: on the first launch
/// after settings became per-character, nothing has been written under anyone's
/// own keys, and every character has to go on looking exactly as the app looked
/// the day before.
final class AppearanceKeyTests: XCTestCase {
    private let miku = UUID(uuidString: "5B1E2A00-0000-4000-8000-000000000001")!
    private let anya = UUID(uuidString: "5B1E2A00-0000-4000-8000-000000000002")!

    private func emptyDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "AppearanceKeyTests.\(name)")!
        defaults.removePersistentDomain(forName: "AppearanceKeyTests.\(name)")
        return defaults
    }

    func testACharacterGetsHerOwnKeyAndTheSharedOneKeepsItsName() {
        XCTAssertEqual(appearanceKey("theme", character: nil), "appearance.theme")
        XCTAssertEqual(
            appearanceKey("theme", character: miku),
            "appearance.\(miku.uuidString).theme"
        )
        XCTAssertNotEqual(
            appearanceKey("theme", character: miku),
            appearanceKey("theme", character: anya)
        )
    }

    // MARK: - Reading

    /// The upgrade case. One theme was chosen back when there was one to choose,
    /// and every character starts from it rather than snapping to the default.
    func testACharacterWithNothingOfHerOwnReadsTheSharedSetting() {
        let defaults = emptyDefaults()
        defaults.set("light", forKey: "appearance.theme")
        defaults.set(17.0, forKey: "appearance.fontSize")

        let hers = UserDefaultsAppearanceStore(defaults: defaults, character: miku).load()

        XCTAssertEqual(hers.theme, .light)
        XCTAssertEqual(hers.fontSize, 17)
    }

    func testHerOwnSettingWinsOverTheSharedOne() {
        let defaults = emptyDefaults()
        defaults.set("light", forKey: "appearance.theme")
        defaults.set("dark", forKey: appearanceKey("theme", character: miku))

        XCTAssertEqual(
            UserDefaultsAppearanceStore(defaults: defaults, character: miku).load().theme,
            .dark
        )
    }

    /// Per setting, not all-or-nothing: choosing a theme must not also freeze
    /// her text size at the default.
    func testSheFallsBackPerSettingRatherThanAsAWhole() {
        let defaults = emptyDefaults()
        defaults.set(19.0, forKey: "appearance.fontSize")
        defaults.set("dark", forKey: appearanceKey("theme", character: miku))

        let hers = UserDefaultsAppearanceStore(defaults: defaults, character: miku).load()

        XCTAssertEqual(hers.theme, .dark)
        XCTAssertEqual(hers.fontSize, 19, "Only the theme was hers; the size is still the shared one")
    }

    // MARK: - Writing

    func testChangingOneCharacterLeavesTheOtherWhereSheWas() {
        let defaults = emptyDefaults()
        let hers = UserDefaultsAppearanceStore(defaults: defaults, character: miku)
        let theirs = UserDefaultsAppearanceStore(defaults: defaults, character: anya)

        hers.save(StoredAppearance(fontSize: 22, theme: .dark))

        XCTAssertEqual(hers.load().theme, .dark)
        XCTAssertEqual(hers.load().fontSize, 22)
        XCTAssertEqual(theirs.load().theme, .system)
        XCTAssertEqual(theirs.load().fontSize, AppearanceSettings.defaultFontSize)
    }

    /// And it must not write through to the shared keys, which are what every
    /// character who has not chosen anything is still reading — one character
    /// going dark would take all of them with her.
    func testSavingDoesNotDisturbTheSharedSetting() {
        let defaults = emptyDefaults()
        defaults.set("light", forKey: "appearance.theme")

        UserDefaultsAppearanceStore(defaults: defaults, character: miku)
            .save(StoredAppearance(theme: .dark))

        XCTAssertEqual(defaults.string(forKey: "appearance.theme"), "light")
        XCTAssertEqual(
            UserDefaultsAppearanceStore(defaults: defaults, character: anya).load().theme,
            .light
        )
    }

    /// The store with no character is still the one that reads and writes the
    /// shared keys, so nothing that predates characters changed meaning.
    func testTheCharacterlessStoreStillUsesTheOriginalKeys() {
        let defaults = emptyDefaults()

        UserDefaultsAppearanceStore(defaults: defaults).save(StoredAppearance(chatHeight: 512))

        XCTAssertEqual(defaults.object(forKey: "appearance.chatHeight") as? Double, 512)
    }
}
