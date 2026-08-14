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

    /// A scale written by a build with different steps must not break loading.
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

    /// `contrast` was offered in 0.10.197 and removed in 0.10.198. Anyone who
    /// had it selected has that word on disk, and the app must open on the
    /// default rather than refuse to read its own settings — the same handling
    /// a scale from a future build gets.
    func testAThemeThatNoLongerExistsFallsBackToSystem() {
        let defaults = UserDefaults(suiteName: "AppearanceThemeFallbackTests")!
        defaults.removePersistentDomain(forName: "AppearanceThemeFallbackTests")
        defaults.set("contrast", forKey: "appearance.theme")

        XCTAssertEqual(UserDefaultsAppearanceStore(defaults: defaults).load().theme, .system)
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
                characterScale: settings.characterScale
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

    // MARK: - Which face the conversation is set in

    /// The default that fixed the reported bug. The chat used to be drawn with
    /// `monospacedSystemFont`, which has no Thai glyphs, so Thai fell through to
    /// Ayuthaya — wide and heavy enough to be reported as the chat being bold,
    /// while nothing in the app had ever asked for bold.
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

    /// Nobody upgrading has this key, and the face they had was monospaced.
    /// Falling back to what they were looking at would keep the bug they
    /// reported, so the fallback is deliberately the new default rather than
    /// the old behaviour.
    func testAMissingStoredFaceFallsBackToTheSystemFace() {
        let name = "AppearanceFontFallbackTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(14.0, forKey: "appearance.fontSize")

        XCTAssertEqual(UserDefaultsAppearanceStore(defaults: defaults).load().font, .system)
    }

    /// A face written by a build with different choices must not throw away the
    /// rest of the look on the way past.
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

    /// Every choice offered has to be one the settings row can round-trip, or a
    /// button in it silently does nothing.
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

    /// The face is a per-character setting like every other, and reads the
    /// shared value until she has one of her own.
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

    /// Asked for: coming back is *not* stepped — one press is the default width,
    /// from however wide the bubble happens to be.
    func testRestoringGoesStraightToTheDefaultWidth() {
        let base = AppearanceSettings.defaultWidth
        var settings = AppearanceSettings(chatWidth: base * 3, maxWidth: 2000)

        settings.restoreChatWidth()
        XCTAssertEqual(settings.chatWidth, base, "Not ×2 on the way past")

        XCTAssertFalse(settings.canRestoreWidth, "Nothing narrower than the default")
    }

    /// Including from a width that isn't one of the stops at all.
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

    /// A hand-dragged width sits between stops. Widening from there goes to the
    /// next stop up — it must not snap backwards to a narrower one.
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
    /// Every size in the panels is derived from the one the person set, so
    /// nothing stays pinned while the rest of the window grows. The hint under
    /// a control stays smaller than the control's own label, at both ends.
    func testPanelSizesFollowTheTextSizeAndKeepTheirOrder() {
        for fontSize in [10.0, 14.0, 20.0, 32.0] {
            let settings = AppearanceSettings(fontSize: fontSize, chatWidth: 400, chatHeight: 700)
            // At the smallest setting both clamp to the 8pt floor, which is
            // deliberate — below that nothing is readable, so the hint stops
            // shrinking rather than becoming a smaller unreadable thing.
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
    /// Spacing grows with the text, or large type reads as a wall — which is
    /// exactly what shipping the font change without this produced.
    func testPanelSpacingGrowsWithTheText() {
        let small = AppearanceSettings(fontSize: 10, chatWidth: 400, chatHeight: 700)
        let large = AppearanceSettings(fontSize: 32, chatWidth: 400, chatHeight: 700)
        XCTAssertGreaterThan(large.panelSpacing, small.panelSpacing)
        XCTAssertGreaterThan(large.panelPadding, small.panelPadding)
        // The gap between rows stays smaller than the panel's own inset, so
        // rows group inside the panel rather than floating apart in it.
        for settings in [small, large] {
            XCTAssertLessThan(settings.panelSpacing, settings.panelPadding)
        }
    }
}
