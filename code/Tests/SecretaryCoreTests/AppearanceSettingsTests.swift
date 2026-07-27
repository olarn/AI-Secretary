import XCTest
@testable import SecretaryCore

final class AppearanceSettingsTests: XCTestCase {

    // MARK: - Text size

    func testStartsAtTheDefault() {
        let settings = AppearanceSettings()
        XCTAssertEqual(settings.fontSize, AppearanceSettings.defaultFontSize)
        XCTAssertEqual(settings.chatHeight, AppearanceSettings.defaultHeight)
    }

    func testPlusAndMinusStepTheTextSize() {
        var settings = AppearanceSettings(fontSize: 12)
        settings.increaseFontSize()
        XCTAssertEqual(settings.fontSize, 12 + AppearanceSettings.fontStep)
        settings.decreaseFontSize()
        XCTAssertEqual(settings.fontSize, 12)
    }

    /// The specified cap.
    func testTextSizeStopsAt32() {
        var settings = AppearanceSettings(fontSize: 30)
        settings.increaseFontSize()
        XCTAssertEqual(settings.fontSize, 32)

        settings.increaseFontSize()
        XCTAssertEqual(settings.fontSize, 32, "Must not go past the cap")
        XCTAssertFalse(settings.canIncreaseFontSize, "The + button should be disabled here")
    }

    func testTextSizeStopsAtTheFloor() {
        var settings = AppearanceSettings(fontSize: AppearanceSettings.minFontSize)
        settings.decreaseFontSize()
        XCTAssertEqual(settings.fontSize, AppearanceSettings.minFontSize)
        XCTAssertFalse(settings.canDecreaseFontSize)
    }

    /// A value stored by a build with different limits must not survive as-is.
    func testAnOutOfRangeStoredTextSizeIsPulledBack() {
        XCTAssertEqual(AppearanceSettings(fontSize: 200).fontSize, 32)
        XCTAssertEqual(AppearanceSettings(fontSize: 1).fontSize, AppearanceSettings.minFontSize)
    }

    // MARK: - Window height

    /// Asked for: the default is also the smallest it goes.
    func testHeightCannotGoBelowTheDefault() {
        var settings = AppearanceSettings(maxHeight: 1000)
        XCTAssertEqual(settings.chatHeight, AppearanceSettings.defaultHeight)
        XCTAssertFalse(settings.canDecreaseHeight, "Already at the floor")

        settings.decreaseHeight()
        XCTAssertEqual(settings.chatHeight, AppearanceSettings.defaultHeight)
    }

    /// Asked for: no taller than the screen.
    func testHeightCannotGrowPastTheScreen() {
        var settings = AppearanceSettings(chatHeight: 520, maxHeight: 620)
        settings.increaseHeight()
        XCTAssertEqual(settings.chatHeight, 580)

        settings.increaseHeight()
        XCTAssertEqual(settings.chatHeight, 620, "Clamped to the screen, not 640")
        XCTAssertFalse(settings.canIncreaseHeight)
    }

    func testGrowingThenShrinkingReturnsToTheDefault() {
        var settings = AppearanceSettings(maxHeight: 1200)
        settings.increaseHeight()
        settings.increaseHeight()
        XCTAssertEqual(settings.chatHeight, AppearanceSettings.defaultHeight + 120)

        settings.decreaseHeight()
        settings.decreaseHeight()
        settings.decreaseHeight()
        XCTAssertEqual(settings.chatHeight, AppearanceSettings.defaultHeight)
    }

    /// Moving to a smaller display has to pull an over-tall window back in,
    /// otherwise part of the conversation is off-screen with no way to reach it.
    func testMovingToASmallerScreenShrinksTheWindow() {
        var settings = AppearanceSettings(chatHeight: 900, maxHeight: 1000)
        XCTAssertEqual(settings.chatHeight, 900)

        settings.setMaxHeight(700)

        XCTAssertEqual(settings.chatHeight, 700)
        XCTAssertEqual(settings.maxHeight, 700)
    }

    /// A screen shorter than the minimum window is still bounded by the
    /// minimum — better to overflow slightly than to collapse the panel.
    func testATinyScreenDoesNotCollapseTheWindow() {
        var settings = AppearanceSettings()
        settings.setMaxHeight(200)
        XCTAssertEqual(settings.maxHeight, AppearanceSettings.defaultHeight)
        XCTAssertEqual(settings.chatHeight, AppearanceSettings.defaultHeight)
    }

    func testAStoredHeightTallerThanTheScreenIsClampedOnLoad() {
        let settings = AppearanceSettings(chatHeight: 5000, maxHeight: 800)
        XCTAssertEqual(settings.chatHeight, 800)
    }

    // MARK: - Derived sizes

    /// Captions have to grow with the body text, or 32pt replies sit beside
    /// unreadable labels.
    func testSecondaryTextGrowsWithTheBodyText() {
        let small = AppearanceSettings(fontSize: 12)
        let large = AppearanceSettings(fontSize: 32)
        XCTAssertLessThan(small.secondaryFontSize, large.secondaryFontSize)
        XCTAssertGreaterThanOrEqual(small.footnoteFontSize, 8, "Never illegible")
    }

    /// At the default body size a caption keeps the size it was designed at, so
    /// turning the text up is the only thing that ever changes the panel.
    func testScaledSizesAreUnchangedAtTheDefaultBodySize() {
        let settings = AppearanceSettings(fontSize: AppearanceSettings.defaultFontSize)
        XCTAssertEqual(settings.scaled(10), 10, accuracy: 0.0001)
        XCTAssertEqual(settings.scaled(13), 13, accuracy: 0.0001)
    }

    /// The reported bug: +/- grew the replies but left the labels, the composer
    /// and the settings box at their original size.
    func testEveryDerivedSizeGrowsWithTheBodyText() {
        let small = AppearanceSettings(fontSize: 12)
        let large = AppearanceSettings(fontSize: 32)
        for base in [9.0, 10.0, 11.0, 13.0] {
            XCTAssertGreaterThan(
                large.scaled(base),
                small.scaled(base),
                "\(base)pt text must grow with the body"
            )
        }
    }

    /// Proportional, not a fixed offset: a label that is 3/4 of the body at the
    /// default has to still be 3/4 of it at the cap, or the hierarchy collapses.
    func testScalingKeepsTheProportionBetweenSizes() {
        let large = AppearanceSettings(fontSize: 24)
        XCTAssertEqual(large.scaled(10), 20, accuracy: 0.0001)
        XCTAssertEqual(large.scaled(9) / large.scaled(12), 9.0 / 12.0, accuracy: 0.0001)
    }

    /// The floor applies to derived text only — it must not drag small print up
    /// to the body size when the user turns everything down.
    func testDerivedSizesHaveALegibilityFloor() {
        let smallest = AppearanceSettings(fontSize: AppearanceSettings.minFontSize)
        XCTAssertGreaterThanOrEqual(smallest.scaled(1), AppearanceSettings.minDerivedFontSize)
        XCTAssertLessThan(smallest.scaled(9), smallest.fontSize, "Still smaller than the body")
    }

    // MARK: - App size

    /// Asked for: three steps, S and L being ±30% — both measured from M, so
    /// they can't compound into a runaway size.
    func testTheThreeAppSizesAreRelativeToMedium() {
        XCTAssertEqual(AppScale.medium.factor, 1.0)
        XCTAssertEqual(AppScale.small.factor, 0.7, accuracy: 0.0001)
        XCTAssertEqual(AppScale.large.factor, 1.3, accuracy: 0.0001)
        XCTAssertEqual(AppScale.allCases.count, 3)
    }

    func testTheCurrentSizeIsTheDefault() {
        XCTAssertEqual(AppearanceSettings().appScale, .medium)
    }

    func testTheAppSizeIsRemembered() {
        let store = InMemoryAppearanceStore()
        store.save(fontSize: 12, chatHeight: 520, appScale: .large)
        XCTAssertEqual(store.load().appScale, .large)
    }

    /// A scale written by a build with different steps must not break loading.
    func testAnUnknownStoredScaleFallsBackToMedium() {
        let defaults = UserDefaults(suiteName: "AppearanceScaleFallbackTests")!
        defaults.removePersistentDomain(forName: "AppearanceScaleFallbackTests")
        defaults.set("enormous", forKey: "appearance.appScale")

        XCTAssertEqual(UserDefaultsAppearanceStore(defaults: defaults).load().appScale, .medium)
    }

    // MARK: - Persistence

    func testTheChoiceIsSavedAndReloaded() {
        let store = InMemoryAppearanceStore()
        var settings = AppearanceSettings(maxHeight: 1200)
        settings.increaseFontSize()
        settings.increaseHeight()
        store.save(
            fontSize: settings.fontSize,
            chatHeight: settings.chatHeight,
            appScale: settings.appScale
        )

        let reloaded = store.load()
        XCTAssertEqual(reloaded.fontSize, 14)
        XCTAssertEqual(reloaded.chatHeight, AppearanceSettings.defaultHeight + 60)
    }

    /// The screen limit is deliberately not persisted — the display can change.
    func testAFreshStoreReturnsTheDefaults() {
        let reloaded = InMemoryAppearanceStore().load()
        XCTAssertEqual(reloaded.fontSize, AppearanceSettings.defaultFontSize)
        XCTAssertEqual(reloaded.chatHeight, AppearanceSettings.defaultHeight)
    }
}
