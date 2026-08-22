import Foundation

public protocol BrowserPreferenceStoring: AnyObject, Sendable {
    var browserEnabled: Bool { get set }
}

public final class UserDefaultsBrowserPreference: BrowserPreferenceStoring, @unchecked Sendable {
    private let key = "browserEnabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var browserEnabled: Bool {
        get { (defaults.object(forKey: key) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: key) }
    }
}

public final class InMemoryBrowserPreference: BrowserPreferenceStoring, @unchecked Sendable {
    public var browserEnabled: Bool
    public init(browserEnabled: Bool = false) { self.browserEnabled = browserEnabled }
}
