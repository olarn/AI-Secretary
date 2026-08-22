import XCTest
@testable import SecretaryCore

final class AppearanceSettingsTests: XCTestCase {

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

    func testAnOutOfRangeStoredTextSizeIsPulledBack() {
        XCTAssertEqual(AppearanceSettings(fontSize: 200).fontSize, 32)
        XCTAssertEqual(AppearanceSettings(fontSize: 1).fontSize, AppearanceSettings.minFontSize)
    }

    func testHeightCannotGoBelowTheDefault() {
        var settings = AppearanceSettings(maxHeight: 1000)
        XCTAssertEqual(settings.chatHeight, AppearanceSettings.defaultHeight)
        XCTAssertFalse(settings.canDecreaseHeight, "Already at the floor")

        settings.decreaseHeight()
        XCTAssertEqual(settings.chatHeight, AppearanceSettings.defaultHeight)
    }

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

    func testMovingToASmallerScreenShrinksTheWindow() {
        var settings = AppearanceSettings(chatHeight: 900, maxHeight: 1000)
        XCTAssertEqual(settings.chatHeight, 900)

        settings.setMaxHeight(700)

        XCTAssertEqual(settings.chatHeight, 700)
        XCTAssertEqual(settings.maxHeight, 700)
    }

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

    func testSecondaryTextGrowsWithTheBodyText() {
        let small = AppearanceSettings(fontSize: 12)
        let large = AppearanceSettings(fontSize: 32)
        XCTAssertLessThan(small.secondaryFontSize, large.secondaryFontSize)
        XCTAssertGreaterThanOrEqual(small.footnoteFontSize, 8, "Never illegible")
    }

    func testTheThreeAppSizesAreRelativeToMedium() {
        XCTAssertEqual(CharacterScale.medium.factor, 1.0)
        XCTAssertEqual(CharacterScale.small.factor, 0.7, accuracy: 0.0001)
        XCTAssertEqual(CharacterScale.large.factor, 1.3, accuracy: 0.0001)
        XCTAssertEqual(CharacterScale.allCases.count, 3)
    }

    func testTheCurrentSizeIsTheDefault() {
        XCTAssertEqual(AppearanceSettings().characterScale, .medium)
    }

    func testTheAppSizeIsRemembered() {
        let store = InMemoryAppearanceStore()
        store.save(StoredAppearance(characterScale: .large))
        XCTAssertEqual(store.load().characterScale, .large)
    }

    func testAnUnknownStoredScaleFallsBackToMedium() {
        let defaults = UserDefaults(suiteName: "AppearanceScaleFallbackTests")!
        defaults.removePersistentDomain(forName: "AppearanceScaleFallbackTests")
        defaults.set("enormous", forKey: "appearance.appScale")

        XCTAssertEqual(UserDefaultsAppearanceStore(defaults: defaults).load().characterScale, .medium)
    }

    func testTheThemeIsSavedAndReloaded() {
        let defaults = UserDefaults(suiteName: "AppearanceThemeTests")!
        defaults.removePersistentDomain(forName: "AppearanceThemeTests")
        let store = UserDefaultsAppearanceStore(defaults: defaults)

        store.save(StoredAppearance(theme: .light))

        XCTAssertEqual(store.load().theme, .light)
    }

    func testAThemeThatNoLongerExistsFallsBackToSystem() {
        let defaults = UserDefaults(suiteName: "AppearanceThemeFallbackTests")!
        defaults.removePersistentDomain(forName: "AppearanceThemeFallbackTests")
        defaults.set("contrast", forKey: "appearance.theme")

        XCTAssertEqual(UserDefaultsAppearanceStore(defaults: defaults).load().theme, .system)
    }

    func testLiquidGlassIsOffByDefault() {
        XCTAssertFalse(AppearanceSettings().liquidGlass)
        XCTAssertFalse(StoredAppearance().liquidGlass)
    }

    func testLiquidGlassSurvivesQuitting() {
        let name = "AppearanceLiquidGlassRoundTripTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = UserDefaultsAppearanceStore(defaults: defaults)

        store.save(StoredAppearance(liquidGlass: true))

        XCTAssertTrue(store.load().liquidGlass)
    }

    func testAMissingStoredLiquidGlassFallsBackToOff() {
        let name = "AppearanceLiquidGlassFallbackTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(14.0, forKey: "appearance.fontSize")

        XCTAssertFalse(UserDefaultsAppearanceStore(defaults: defaults).load().liquidGlass)
    }

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
                characterScale: settings.characterScale
            )
        )

        let reloaded = store.load()
        XCTAssertEqual(reloaded.fontSize, 14)
        XCTAssertEqual(reloaded.chatWidth, 900)
        XCTAssertEqual(reloaded.chatHeight, AppearanceSettings.defaultHeight + 60)
    }

    func testAFreshStoreReturnsTheDefaults() {
        let reloaded = InMemoryAppearanceStore().load()
        XCTAssertEqual(reloaded.fontSize, AppearanceSettings.defaultFontSize)
        XCTAssertEqual(reloaded.chatWidth, AppearanceSettings.defaultWidth)
        XCTAssertEqual(reloaded.chatHeight, AppearanceSettings.defaultHeight)
    }

    func testAMissingStoredWidthFallsBackToTheDefault() {
        let name = "AppearanceWidthFallbackTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(14.0, forKey: "appearance.fontSize")

        let reloaded = UserDefaultsAppearanceStore(defaults: defaults).load()
        XCTAssertEqual(reloaded.fontSize, 14)
        XCTAssertEqual(reloaded.chatWidth, AppearanceSettings.defaultWidth)
    }

    func testTheConversationIsSetInTheSystemFaceByDefault() {
        XCTAssertEqual(AppearanceSettings().font, .system)
        XCTAssertEqual(StoredAppearance().font, .system)
    }

    func testTheChosenFaceSurvivesQuitting() {
        let name = "AppearanceFontRoundTripTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = UserDefaultsAppearanceStore(defaults: defaults)

        store.save(StoredAppearance(font: .serif))

        XCTAssertEqual(store.load().font, .serif)
    }

    func testAMissingStoredFaceFallsBackToTheSystemFace() {
        let name = "AppearanceFontFallbackTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(14.0, forKey: "appearance.fontSize")

        XCTAssertEqual(UserDefaultsAppearanceStore(defaults: defaults).load().font, .system)
    }

    func testAnUnrecognisedFaceFallsBackWithoutLosingTheOtherSettings() {
        let name = "AppearanceFontUnknownTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set("blackletter", forKey: "appearance.fontDesign")
        defaults.set(18.0, forKey: "appearance.fontSize")

        let reloaded = UserDefaultsAppearanceStore(defaults: defaults).load()
        XCTAssertEqual(reloaded.font, .system)
        XCTAssertEqual(reloaded.fontSize, 18)
    }

    func testEveryOfferedFaceHasALabelAnExplanationAndSurvives() {
        let name = "AppearanceFontAllCasesTests"
        let defaults = UserDefaults(suiteName: name)!
        for choice in FontChoice.allCases {
            defaults.removePersistentDomain(forName: name)
            let store = UserDefaultsAppearanceStore(defaults: defaults)
            store.save(StoredAppearance(font: choice))
            XCTAssertEqual(store.load().font, choice)
            XCTAssertFalse(choice.label.isEmpty)
            XCTAssertFalse(choice.explanation.isEmpty)
        }
    }

    func testACharacterReadsTheSharedFaceUntilSheIsGivenOne() {
        let name = "AppearanceFontPerCharacterTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let her = UUID()
        defaults.set("serif", forKey: "appearance.fontDesign")

        let hers = UserDefaultsAppearanceStore(defaults: defaults, character: her)
        XCTAssertEqual(hers.load().font, .serif, "Nothing of her own yet — she reads the shared look")

        hers.save(StoredAppearance(font: .rounded))
        XCTAssertEqual(hers.load().font, .rounded)
        XCTAssertEqual(
            UserDefaultsAppearanceStore(defaults: defaults).load().font, .serif,
            "Her choice must not move everyone who hasn't made one"
        )
    }

    func testWidthStartsAtTheDefaultAndIsItsFloor() {
        var settings = AppearanceSettings(maxWidth: 2000)
        XCTAssertEqual(settings.chatWidth, AppearanceSettings.defaultWidth)

        settings.setChatSize(width: 100, height: settings.chatHeight)
        XCTAssertEqual(settings.chatWidth, AppearanceSettings.defaultWidth)
    }

    func testDraggingSetsBothAxesAndClampsToTheScreen() {
        var settings = AppearanceSettings(maxWidth: 1000, maxHeight: 800)
        settings.setChatSize(width: 640, height: 700)
        XCTAssertEqual(settings.chatWidth, 640)
        XCTAssertEqual(settings.chatHeight, 700)

        settings.setChatSize(width: 5000, height: 5000)
        XCTAssertEqual(settings.chatWidth, 1000)
        XCTAssertEqual(settings.chatHeight, 800)
    }

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

    func testRestoringGoesStraightToTheDefaultWidth() {
        let base = AppearanceSettings.defaultWidth
        var settings = AppearanceSettings(chatWidth: base * 3, maxWidth: 2000)

        settings.restoreChatWidth()
        XCTAssertEqual(settings.chatWidth, base, "Not ×2 on the way past")

        XCTAssertFalse(settings.canRestoreWidth, "Nothing narrower than the default")
    }

    func testRestoringFromAHandDraggedWidthAlsoGoesToTheDefault() {
        var settings = AppearanceSettings(maxWidth: 2000)
        settings.setChatSize(width: 940, height: settings.chatHeight)
        XCTAssertTrue(settings.canRestoreWidth)

        settings.restoreChatWidth()
        XCTAssertEqual(settings.chatWidth, AppearanceSettings.defaultWidth)
    }

    func testTheWidthButtonsAreBothLiveInTheMiddleOfTheRange() {
        let settings = AppearanceSettings(chatWidth: AppearanceSettings.defaultWidth * 2, maxWidth: 2000)
        XCTAssertTrue(settings.canWiden)
        XCTAssertTrue(settings.canRestoreWidth)
    }

    func testStopsAreCappedToTheScreenAndNotRepeated() {
        var settings = AppearanceSettings(maxWidth: 800)
        XCTAssertEqual(settings.widthStops, [360, 720, 800])

        settings.widenChat()
        XCTAssertEqual(settings.chatWidth, 720)
        settings.widenChat()
        XCTAssertEqual(settings.chatWidth, 800)
        XCTAssertFalse(settings.canWiden)
    }

    func testATinyScreenLeavesASingleStop() {
        let settings = AppearanceSettings(maxWidth: 300)
        XCTAssertEqual(settings.widthStops, [AppearanceSettings.defaultWidth])
        XCTAssertFalse(settings.canWiden)
        XCTAssertFalse(settings.canRestoreWidth)
    }

    func testWideningFromAHandDraggedWidthGoesToTheNextStopUp() {
        var settings = AppearanceSettings(maxWidth: 2000)
        settings.setChatSize(width: 500, height: settings.chatHeight)

        settings.widenChat()
        XCTAssertEqual(settings.chatWidth, 720, "Up to ×2, not back down to ×1")
    }

    func testMovingToANarrowerScreenPullsTheWidthBackIn() {
        var settings = AppearanceSettings(chatWidth: 900, maxWidth: 1000)
        settings.setMaxWidth(600)
        XCTAssertEqual(settings.chatWidth, 600)
        XCTAssertEqual(settings.maxWidth, 600)
    }
}

extension AppearanceSettingsTests {
    func testPanelSizesFollowTheTextSizeAndKeepTheirOrder() {
        for fontSize in [10.0, 14.0, 20.0, 32.0] {
            let settings = AppearanceSettings(fontSize: fontSize, chatWidth: 400, chatHeight: 700)
            XCTAssertLessThanOrEqual(settings.hintFontSize, settings.footnoteFontSize, "at \(fontSize)pt")
            XCTAssertLessThanOrEqual(settings.footnoteFontSize, settings.fontSize, "at \(fontSize)pt")
        }
        let readable = AppearanceSettings(fontSize: 14, chatWidth: 400, chatHeight: 700)
        XCTAssertLessThan(readable.hintFontSize, readable.footnoteFontSize, "above the floor they differ")
        let small = AppearanceSettings(fontSize: 10, chatWidth: 400, chatHeight: 700)
        let large = AppearanceSettings(fontSize: 32, chatWidth: 400, chatHeight: 700)
        XCTAssertGreaterThan(large.hintFontSize, small.hintFontSize)
    }
}

extension AppearanceSettingsTests {
    func testPanelSpacingGrowsWithTheText() {
        let small = AppearanceSettings(fontSize: 10, chatWidth: 400, chatHeight: 700)
        let large = AppearanceSettings(fontSize: 32, chatWidth: 400, chatHeight: 700)
        XCTAssertGreaterThan(large.panelSpacing, small.panelSpacing)
        XCTAssertGreaterThan(large.panelPadding, small.panelPadding)
        for settings in [small, large] {
            XCTAssertLessThan(settings.panelSpacing, settings.panelPadding)
        }
    }
}

extension AppearanceSettingsTests {
    func testTheChatReadsTheSameSizesThroughTheExtractedMetrics() {
        for fontSize in stride(from: 10.0, through: 32.0, by: 2.0) {
            let settings = AppearanceSettings(fontSize: fontSize, chatWidth: 400, chatHeight: 700)
            let metrics = TextMetrics(fontSize: fontSize)
            XCTAssertEqual(settings.secondaryFontSize, metrics.secondaryFontSize, "at \(fontSize)pt")
            XCTAssertEqual(settings.footnoteFontSize, metrics.footnoteFontSize, "at \(fontSize)pt")
            XCTAssertEqual(settings.captionFontSize, metrics.captionFontSize, "at \(fontSize)pt")
            XCTAssertEqual(settings.hintFontSize, metrics.hintFontSize, "at \(fontSize)pt")
            XCTAssertEqual(settings.panelSpacing, metrics.panelSpacing, "at \(fontSize)pt")
            XCTAssertEqual(settings.panelPadding, metrics.panelPadding, "at \(fontSize)pt")
        }
    }

    func testMetricsFromABiggerSizeAreBiggerThroughout() {
        let small = TextMetrics(fontSize: 12)
        let large = TextMetrics(fontSize: 24)
        XCTAssertGreaterThan(large.footnoteFontSize, small.footnoteFontSize)
        XCTAssertGreaterThan(large.hintFontSize, small.hintFontSize)
        XCTAssertGreaterThan(large.panelSpacing, small.panelSpacing)
        XCTAssertGreaterThan(large.panelPadding, small.panelPadding)
    }
}
