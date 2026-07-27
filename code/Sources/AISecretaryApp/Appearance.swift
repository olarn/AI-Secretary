import AppKit
import Observation
import SecretaryCore

/// The live text-size and window-height choice, shared by the panel that
/// changes it and the window that has to resize.
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
    @ObservationIgnored private let store: AppearanceStoring
    @ObservationIgnored var onChange: (() -> Void)?

    init(store: AppearanceStoring = UserDefaultsAppearanceStore()) {
        self.store = store
        let saved = store.load()
        self.settings = AppearanceSettings(
            fontSize: saved.fontSize,
            chatHeight: saved.chatHeight,
            maxHeight: Self.usableScreenHeight
        )
    }

    /// The height of the screen minus the menu bar and Dock — what a window can
    /// actually occupy, rather than the raw display size.
    static var usableScreenHeight: Double {
        NSScreen.main.map { Double($0.visibleFrame.height) } ?? AppearanceSettings.defaultHeight
    }

    /// Re-applies the screen limit. Worth doing when the panel is about to be
    /// shown, since the display may have changed since launch.
    func refreshScreenLimit() {
        var updated = settings
        updated.setMaxHeight(Self.usableScreenHeight)
        apply(updated)
    }

    func increaseFontSize() { mutate { $0.increaseFontSize() } }
    func decreaseFontSize() { mutate { $0.decreaseFontSize() } }
    func increaseHeight() { mutate { $0.increaseHeight() } }
    func decreaseHeight() { mutate { $0.decreaseHeight() } }

    private func mutate(_ change: (inout AppearanceSettings) -> Void) {
        var updated = settings
        change(&updated)
        apply(updated)
    }

    private func apply(_ updated: AppearanceSettings) {
        guard updated != settings else { return }
        let heightChanged = updated.chatHeight != settings.chatHeight
        settings = updated
        store.save(fontSize: updated.fontSize, chatHeight: updated.chatHeight)
        if heightChanged { onChange?() }
    }
}
