import XCTest
@testable import SecretaryCore

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

    func testSheFallsBackPerSettingRatherThanAsAWhole() {
        let defaults = emptyDefaults()
        defaults.set(19.0, forKey: "appearance.fontSize")
        defaults.set("dark", forKey: appearanceKey("theme", character: miku))

        let hers = UserDefaultsAppearanceStore(defaults: defaults, character: miku).load()

        XCTAssertEqual(hers.theme, .dark)
        XCTAssertEqual(hers.fontSize, 19, "Only the theme was hers; the size is still the shared one")
    }

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

    func testTheCharacterlessStoreStillUsesTheOriginalKeys() {
        let defaults = emptyDefaults()

        UserDefaultsAppearanceStore(defaults: defaults).save(StoredAppearance(chatHeight: 512))

        XCTAssertEqual(defaults.object(forKey: "appearance.chatHeight") as? Double, 512)
    }
}
