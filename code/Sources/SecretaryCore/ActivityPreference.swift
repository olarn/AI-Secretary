import Foundation

/// Remembers whether the user wants to see what the assistant is doing.
///
/// Separated so it can be swapped in tests, and because the default matters:
/// a first run is quiet, and the setting only exists once someone has chosen.
public protocol ActivityPreferenceStoring: AnyObject, Sendable {
    var showsActivity: Bool { get set }
}

/// Backed by user defaults, so the choice survives quitting the app.
public final class UserDefaultsActivityPreference: ActivityPreferenceStoring, @unchecked Sendable {
    private let key = "showsActivity"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Hidden until asked for: the default experience is a companion that
    /// answers, not a progress log. `object(forKey:)` rather than `bool` so an
    /// unset value is false by intent rather than by accident.
    public var showsActivity: Bool {
        get { (defaults.object(forKey: key) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: key) }
    }
}

/// For tests.
public final class InMemoryActivityPreference: ActivityPreferenceStoring, @unchecked Sendable {
    public var showsActivity: Bool
    public init(showsActivity: Bool = false) { self.showsActivity = showsActivity }
}
