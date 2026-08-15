import AppKit
import Observation
import SecretaryCore

/// One character's look: her text size, her window height, how big she is
/// drawn, and her theme. Shared by the panel that changes it and the window
/// that has to resize.
///
/// One of these per character since 13-1. The app-wide windows — Token Usage,
/// About — have no character of their own, so they follow whichever character
/// was used last; see `AppDelegate.focused`.
///
/// The rules live in `AppearanceSettings`; this holds the current value,
/// persists every change, and tells the window when to resize. `onChange` is a
/// callback rather than the delegate observing the object, because resizing an
/// `NSPanel` is imperative work that has to happen once per change, not
/// re-derived during a view update.
@MainActor
@Observable
final class Appearance {
    private(set) var settings: AppearanceSettings
    /// Whether macOS is currently in dark mode. Stored and observed rather than
    /// read where it's needed: the `System` theme has to repaint when the user
    /// flips the system setting, and a value read inside a `body` is not
    /// something SwiftUI knows to re-read.
    private(set) var systemIsDark: Bool
    @ObservationIgnored private let store: AppearanceStoring
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var systemThemeObserver: NSObjectProtocol?

    convenience init(character: UUID) {
        self.init(store: UserDefaultsAppearanceStore(character: character))
    }

    init(store: AppearanceStoring = UserDefaultsAppearanceStore()) {
        self.store = store
        self.systemIsDark = Self.readSystemIsDark()
        let saved = store.load()
        // No screen to measure means no limit to apply, so the saved size stands
        // as its own ceiling. Falling back to the default here would shrink a
        // window the user had deliberately grown.
        let screen = NSScreen.main?.visibleFrame
        self.settings = AppearanceSettings(
            fontSize: saved.fontSize,
            chatWidth: saved.chatWidth,
            chatHeight: saved.chatHeight,
            maxWidth: screen.map(Self.usableWidth) ?? saved.chatWidth,
            maxHeight: screen.map { Double($0.height) } ?? saved.chatHeight,
            characterScale: saved.characterScale,
            theme: saved.theme,
            font: saved.font
        )
        watchSystemTheme()
    }

    /// The colours everything is painted with right now.
    ///
    /// Module-qualified because the property and the function that computes it
    /// share a name, which is the right name for both.
    var colors: Palette {
        SecretaryCore.palette(for: settings.theme, systemIsDark: systemIsDark)
    }

    private static func readSystemIsDark() -> Bool {
        NSApp?.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// AppKit posts this on the distributed centre when the user changes the
    /// system's light/dark setting. Without it, `System` would only be re-read
    /// at launch — the app would keep its old palette until relaunched, which
    /// looks exactly like the setting not working.
    private func watchSystemTheme() {
        systemThemeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let nowDark = Self.readSystemIsDark()
                guard nowDark != self.systemIsDark else { return }
                self.systemIsDark = nowDark
                // Only `System` is following it; the other two are the user
                // saying the system setting is not what they want.
                if self.settings.theme == .system { self.onChange?() }
            }
        }
    }

    private static func usableWidth(_ visibleFrame: CGRect) -> Double {
        Double(usableBubbleWidth(visibleFrame.width))
    }

    /// Re-applies the limits of the screen the character is actually on. Worth
    /// doing when the panel is about to be shown, since the display may have
    /// changed since launch.
    ///
    /// A `nil` frame leaves the limits alone: an unknown screen is not the same
    /// as a tiny one, and treating it as tiny would collapse the window and
    /// leave the widen button dead with no way to explain why.
    func applyScreenLimits(_ visibleFrame: CGRect?) {
        guard let visibleFrame else { return }
        var updated = settings
        updated.setMaxHeight(Double(visibleFrame.height))
        updated.setMaxWidth(Self.usableWidth(visibleFrame))
        apply(updated)
    }

    func increaseFontSize() { mutate { $0.increaseFontSize() } }
    func decreaseFontSize() { mutate { $0.decreaseFontSize() } }
    func increaseHeight() { mutate { $0.increaseHeight() } }
    func decreaseHeight() { mutate { $0.decreaseHeight() } }
    func selectCharacterScale(_ scale: CharacterScale) { mutate { $0.characterScale = scale } }
    func selectTheme(_ theme: ThemeChoice) { mutate { $0.theme = theme } }
    func selectFont(_ font: FontChoice) { mutate { $0.font = font } }
    func widenChat() { mutate { $0.widenChat() } }
    func restoreChatWidth() { mutate { $0.restoreChatWidth() } }
    func resizeChat(width: Double, height: Double) {
        mutate { $0.setChatSize(width: width, height: height) }
    }

    private func mutate(_ change: (inout AppearanceSettings) -> Void) {
        var updated = settings
        change(&updated)
        apply(updated)
    }

    private func apply(_ updated: AppearanceSettings) {
        guard updated != settings else { return }
        // The character window is resized imperatively too, so a scale change
        // has to reach the delegate the same way a height change does.
        // A theme change is imperative work on the window too: the control
        // appearance is an AppKit property, not something a SwiftUI body can
        // return, so it goes through the same callback as a resize.
        let needsRelayout = updated.chatHeight != settings.chatHeight
            || updated.chatWidth != settings.chatWidth
            || updated.characterScale != settings.characterScale
            || updated.theme != settings.theme
        settings = updated
        store.save(
            StoredAppearance(
                fontSize: updated.fontSize,
                chatWidth: updated.chatWidth,
                chatHeight: updated.chatHeight,
                characterScale: updated.characterScale,
                theme: updated.theme,
                font: updated.font
            )
        )
        if needsRelayout { onChange?() }
    }
}
