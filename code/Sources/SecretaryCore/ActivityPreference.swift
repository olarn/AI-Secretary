import Foundation

public protocol ActivityPreferenceStoring: AnyObject, Sendable {
    var showsActivity: Bool { get set }
}

public final class UserDefaultsActivityPreference: ActivityPreferenceStoring, @unchecked Sendable {
    private let key = "showsActivity"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var showsActivity: Bool {
        get { (defaults.object(forKey: key) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: key) }
    }
}

public final class InMemoryActivityPreference: ActivityPreferenceStoring, @unchecked Sendable {
    public var showsActivity: Bool
    public init(showsActivity: Bool = false) { self.showsActivity = showsActivity }
}
