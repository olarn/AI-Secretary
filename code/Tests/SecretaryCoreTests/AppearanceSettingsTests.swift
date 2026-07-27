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

    // MARK: - Persistence

    func testTheChoiceIsSavedAndReloaded() {
        let store = InMemoryAppearanceStore()
        var settings = AppearanceSettings(maxHeight: 1200)
        settings.increaseFontSize()
        settings.increaseHeight()
        store.save(fontSize: settings.fontSize, chatHeight: settings.chatHeight)

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
