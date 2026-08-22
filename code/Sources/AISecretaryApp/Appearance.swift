import AppKit
import Observation
import SecretaryCore

@MainActor
@Observable
final class Appearance {
    private(set) var settings: AppearanceSettings
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
        let screen = NSScreen.main?.visibleFrame
        self.settings = AppearanceSettings(
            fontSize: saved.fontSize,
            chatWidth: saved.chatWidth,
            chatHeight: saved.chatHeight,
            maxWidth: screen.map(Self.usableWidth) ?? saved.chatWidth,
            maxHeight: screen.map { Double($0.height) } ?? saved.chatHeight,
            characterScale: saved.characterScale,
            theme: saved.theme,
            font: saved.font,
            liquidGlass: saved.liquidGlass
        )
        watchSystemTheme()
    }

    var colors: Palette {
        SecretaryCore.palette(for: settings.theme, systemIsDark: systemIsDark)
    }

    private static func readSystemIsDark() -> Bool {
        NSApp?.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

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
                if self.settings.theme == .system { self.onChange?() }
            }
        }
    }

    private static func usableWidth(_ visibleFrame: CGRect) -> Double {
        Double(usableBubbleWidth(visibleFrame.width))
    }

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
    func setLiquidGlass(_ on: Bool) { mutate { $0.liquidGlass = on } }
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
        let needsRelayout = updated.chatHeight != settings.chatHeight
            || updated.chatWidth != settings.chatWidth
            || updated.characterScale != settings.characterScale
            || updated.theme != settings.theme
            || updated.liquidGlass != settings.liquidGlass
        settings = updated
        store.save(
            StoredAppearance(
                fontSize: updated.fontSize,
                chatWidth: updated.chatWidth,
                chatHeight: updated.chatHeight,
                characterScale: updated.characterScale,
                theme: updated.theme,
                font: updated.font,
                liquidGlass: updated.liquidGlass
            )
        )
        if needsRelayout { onChange?() }
    }
}
