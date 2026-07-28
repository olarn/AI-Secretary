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
        store.save(StoredAppearance(appScale: .large))
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
        var settings = AppearanceSettings(maxWidth: 2000, maxHeight: 1200)
        settings.increaseFontSize()
        settings.increaseHeight()
        settings.setChatSize(width: 900, height: settings.chatHeight)
        store.save(
            StoredAppearance(
                fontSize: settings.fontSize,
                chatWidth: settings.chatWidth,
                chatHeight: settings.chatHeight,
                appScale: settings.appScale
            )
        )

        let reloaded = store.load()
        XCTAssertEqual(reloaded.fontSize, 14)
        XCTAssertEqual(reloaded.chatWidth, 900)
        XCTAssertEqual(reloaded.chatHeight, AppearanceSettings.defaultHeight + 60)
    }

    /// The screen limit is deliberately not persisted — the display can change.
    func testAFreshStoreReturnsTheDefaults() {
        let reloaded = InMemoryAppearanceStore().load()
        XCTAssertEqual(reloaded.fontSize, AppearanceSettings.defaultFontSize)
        XCTAssertEqual(reloaded.chatWidth, AppearanceSettings.defaultWidth)
        XCTAssertEqual(reloaded.chatHeight, AppearanceSettings.defaultHeight)
    }

    /// Width was added after the other two, so anyone upgrading has no value
    /// stored. Falling back to zero would collapse the bubble.
    func testAMissingStoredWidthFallsBackToTheDefault() {
        let name = "AppearanceWidthFallbackTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(14.0, forKey: "appearance.fontSize")

        let reloaded = UserDefaultsAppearanceStore(defaults: defaults).load()
        XCTAssertEqual(reloaded.fontSize, 14)
        XCTAssertEqual(reloaded.chatWidth, AppearanceSettings.defaultWidth)
    }

    // MARK: - Window width

    func testWidthStartsAtTheDefaultAndIsItsFloor() {
        var settings = AppearanceSettings(maxWidth: 2000)
        XCTAssertEqual(settings.chatWidth, AppearanceSettings.defaultWidth)

        settings.setChatSize(width: 100, height: settings.chatHeight)
        XCTAssertEqual(settings.chatWidth, AppearanceSettings.defaultWidth)
    }

    /// Free resize, as asked — but still inside the screen.
    func testDraggingSetsBothAxesAndClampsToTheScreen() {
        var settings = AppearanceSettings(maxWidth: 1000, maxHeight: 800)
        settings.setChatSize(width: 640, height: 700)
        XCTAssertEqual(settings.chatWidth, 640)
        XCTAssertEqual(settings.chatHeight, 700)

        settings.setChatSize(width: 5000, height: 5000)
        XCTAssertEqual(settings.chatWidth, 1000)
        XCTAssertEqual(settings.chatHeight, 800)
    }

    /// Asked for: one press is one step — ×1 → ×2 → ×3 — and then the button is
    /// dead rather than jumping straight to the widest.
    func testWideningStepsThroughOneTwoAndThreeTimes() {
        let base = AppearanceSettings.defaultWidth
        var settings = AppearanceSettings(maxWidth: 2000)
        XCTAssertEqual(settings.chatWidth, base)

        settings.widenChat()
        XCTAssertEqual(settings.chatWidth, base * 2)

        settings.widenChat()
        XCTAssertEqual(settings.chatWidth, base * 3)

        XCTAssertFalse(settings.canWiden, "Three times is the last step")
        settings.widenChat()
        XCTAssertEqual(settings.chatWidth, base * 3, "A dead button changes nothing")
    }

    /// And back down the same way.
    func testRestoringStepsBackDownToTheDefault() {
        let base = AppearanceSettings.defaultWidth
        var settings = AppearanceSettings(chatWidth: base * 3, maxWidth: 2000)

        settings.restoreChatWidth()
        XCTAssertEqual(settings.chatWidth, base * 2)

        settings.restoreChatWidth()
        XCTAssertEqual(settings.chatWidth, base)

        XCTAssertFalse(settings.canRestoreWidth, "Nothing narrower than the default")
        settings.restoreChatWidth()
        XCTAssertEqual(settings.chatWidth, base)
    }

    func testTheWidthButtonsAreBothLiveInTheMiddleOfTheRange() {
        let settings = AppearanceSettings(chatWidth: AppearanceSettings.defaultWidth * 2, maxWidth: 2000)
        XCTAssertTrue(settings.canWiden)
        XCTAssertTrue(settings.canRestoreWidth)
    }

    /// Three times the default doesn't fit on every display, and a stop the
    /// screen has squeezed into another one isn't a separate press.
    func testStopsAreCappedToTheScreenAndNotRepeated() {
        var settings = AppearanceSettings(maxWidth: 800)
        XCTAssertEqual(settings.widthStops, [360, 720, 800])

        settings.widenChat()
        XCTAssertEqual(settings.chatWidth, 720)
        settings.widenChat()
        XCTAssertEqual(settings.chatWidth, 800)
        XCTAssertFalse(settings.canWiden)
    }

    /// A screen too narrow for even two steps leaves one stop, so both buttons
    /// are dead rather than pressable with nothing to show for it.
    func testATinyScreenLeavesASingleStop() {
        let settings = AppearanceSettings(maxWidth: 300)
        XCTAssertEqual(settings.widthStops, [AppearanceSettings.defaultWidth])
        XCTAssertFalse(settings.canWiden)
        XCTAssertFalse(settings.canRestoreWidth)
    }

    /// A hand-dragged width sits between stops. Stepping from there goes to the
    /// next stop in that direction — it must not snap the other way.
    func testSteppingFromAHandDraggedWidthGoesToTheNextStop() {
        var settings = AppearanceSettings(maxWidth: 2000)
        settings.setChatSize(width: 500, height: settings.chatHeight)

        settings.widenChat()
        XCTAssertEqual(settings.chatWidth, 720, "Up to ×2, not back down to ×1")

        settings.setChatSize(width: 500, height: settings.chatHeight)
        settings.restoreChatWidth()
        XCTAssertEqual(settings.chatWidth, 360, "Down to ×1")
    }

    func testMovingToANarrowerScreenPullsTheWidthBackIn() {
        var settings = AppearanceSettings(chatWidth: 900, maxWidth: 1000)
        settings.setMaxWidth(600)
        XCTAssertEqual(settings.chatWidth, 600)
        XCTAssertEqual(settings.maxWidth, 600)
    }
}
