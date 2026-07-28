import Foundation

/// Remembers whether the user has connected the assistant to their browser.
///
/// Its own store rather than a field on the profile or the appearance settings:
/// this is a permission, and permissions that reach the user's signed-in
/// sessions shouldn't ride along with a profile picture or a font size, where
/// switching profiles could quietly turn one on.
public protocol BrowserPreferenceStoring: AnyObject, Sendable {
    var browserEnabled: Bool { get set }
}

/// Backed by user defaults, so the choice survives quitting the app.
public final class UserDefaultsBrowserPreference: BrowserPreferenceStoring, @unchecked Sendable {
    private let key = "browserEnabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Off until asked for. Least privilege, and the honest default: connecting
    /// gives the assistant reach into every site the person is signed into, so
    /// it should be a thing they did, not a thing they inherited.
    public var browserEnabled: Bool {
        get { (defaults.object(forKey: key) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: key) }
    }
}

/// For tests.
public final class InMemoryBrowserPreference: BrowserPreferenceStoring, @unchecked Sendable {
    public var browserEnabled: Bool
    public init(browserEnabled: Bool = false) { self.browserEnabled = browserEnabled }
}
