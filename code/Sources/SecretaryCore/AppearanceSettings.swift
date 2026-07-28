import Foundation

/// How big the floating character is on the desktop: three fixed steps, both
/// measured from the current size so they can't compound.
public enum AppScale: String, CaseIterable, Sendable, Codable {
    case small, medium, large

    /// `medium` is what the app has always shipped as, so it's 1.0 and the
    /// other two are ±30% of it.
    public var factor: Double {
        switch self {
        case .small: return 0.7
        case .medium: return 1.0
        case .large: return 1.3
        }
    }

    public var label: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }
}

/// Text size, chat-window height, and character size.
///
/// A value type with the limits built in, rather than two numbers nudged around
/// inside a view, because the edges are the interesting part: the buttons have
/// to stop at the ends rather than appear broken, and a height stored by an
/// older build — or on a bigger display — must not leave the window taller than
/// the screen it's now on.
public struct AppearanceSettings: Equatable, Sendable {
    /// The cap is a product decision: past 32pt the bubble shows so little at
    /// once that every reply needs scrolling.
    public static let minFontSize: Double = 10
    public static let maxFontSize: Double = 32
    public static let fontStep: Double = 2
    public static let defaultFontSize: Double = 12

    /// The default height is also the floor — shrinking below it leaves too
    /// little of the conversation visible to be useful.
    public static let defaultHeight: Double = 520
    public static let heightStep: Double = 60

    /// The width the bubble has always shipped as, and its floor: the tail is
    /// drawn against the width, and much narrower than this the wrapped text
    /// stops being readable.
    public static let defaultWidth: Double = 360
    /// The widths the widen/restore buttons step through, as multiples of the
    /// default. One press is one step, so the jump to three times the width is
    /// something the user arrives at rather than lands on by surprise.
    public static let widthFactors: [Double] = [1, 2, 3]

    public private(set) var fontSize: Double
    public private(set) var chatWidth: Double
    public private(set) var chatHeight: Double
    public var appScale: AppScale

    /// The most the bubble may become: the usable area of the screen it's on.
    /// Deliberately not persisted — the display can change between launches, so
    /// these are supplied each time rather than remembered.
    public private(set) var maxHeight: Double
    public private(set) var maxWidth: Double

    public init(
        fontSize: Double = Self.defaultFontSize,
        chatWidth: Double = Self.defaultWidth,
        chatHeight: Double = Self.defaultHeight,
        maxWidth: Double = Self.defaultWidth,
        maxHeight: Double = Self.defaultHeight,
        appScale: AppScale = .medium
    ) {
        self.appScale = appScale
        self.fontSize = min(max(fontSize, Self.minFontSize), Self.maxFontSize)
        self.maxHeight = max(maxHeight, Self.defaultHeight)
        self.maxWidth = max(maxWidth, Self.defaultWidth)
        self.chatHeight = min(max(chatHeight, Self.defaultHeight), self.maxHeight)
        self.chatWidth = min(max(chatWidth, Self.defaultWidth), self.maxWidth)
    }

    /// Called when the screen is known or changes. Re-clamps the current height,
    /// so moving to a smaller display pulls an over-tall window back in.
    public mutating func setMaxHeight(_ height: Double) {
        maxHeight = max(height, Self.defaultHeight)
        chatHeight = min(chatHeight, maxHeight)
    }

    public mutating func setMaxWidth(_ width: Double) {
        maxWidth = max(width, Self.defaultWidth)
        chatWidth = min(chatWidth, maxWidth)
    }

    // MARK: - Free resizing

    /// A drag on the bubble's grip. Both axes at once, because a corner grip
    /// moves both, and clamped rather than refused so the drag simply stops at
    /// the limit instead of jumping.
    public mutating func setChatSize(width: Double, height: Double) {
        chatWidth = min(max(width, Self.defaultWidth), maxWidth)
        chatHeight = min(max(height, Self.defaultHeight), maxHeight)
    }

    // MARK: - Stepping the width

    /// The stops the two buttons move between, narrowest first. Each is capped
    /// to the screen, and a stop that the screen has squeezed into another one
    /// isn't a separate stop — otherwise a press would appear to do nothing.
    public var widthStops: [Double] {
        var stops: [Double] = []
        for factor in Self.widthFactors {
            let stop = min(Self.defaultWidth * factor, maxWidth)
            if stops.last != stop { stops.append(stop) }
        }
        return stops
    }

    /// The next stop wider than the bubble is now. A hand-dragged width sits
    /// between stops, and stepping from there goes to the next one up rather
    /// than snapping backwards.
    public var nextWiderWidth: Double? {
        widthStops.first { $0 > chatWidth }
    }

    public var nextNarrowerWidth: Double? {
        widthStops.last { $0 < chatWidth }
    }

    public var canWiden: Bool { nextWiderWidth != nil }
    public var canRestoreWidth: Bool { nextNarrowerWidth != nil }

    public mutating func widenChat() {
        guard let next = nextWiderWidth else { return }
        chatWidth = next
    }

    public mutating func restoreChatWidth() {
        guard let previous = nextNarrowerWidth else { return }
        chatWidth = previous
    }

    // MARK: - Stepping

    public mutating func increaseFontSize() {
        fontSize = min(fontSize + Self.fontStep, Self.maxFontSize)
    }

    public mutating func decreaseFontSize() {
        fontSize = max(fontSize - Self.fontStep, Self.minFontSize)
    }

    public mutating func increaseHeight() {
        chatHeight = min(chatHeight + Self.heightStep, maxHeight)
    }

    public mutating func decreaseHeight() {
        chatHeight = max(chatHeight - Self.heightStep, Self.defaultHeight)
    }

    /// Used to dim a button that can't do anything, so pressing nothing looks
    /// intentional rather than broken.
    public var canIncreaseFontSize: Bool { fontSize < Self.maxFontSize }
    public var canDecreaseFontSize: Bool { fontSize > Self.minFontSize }
    public var canIncreaseHeight: Bool { chatHeight < maxHeight }
    public var canDecreaseHeight: Bool { chatHeight > Self.defaultHeight }

    // MARK: - Derived sizes

    /// Secondary text tracks the body size so the panel scales as one piece
    /// instead of leaving captions tiny beside 32pt text.
    public var secondaryFontSize: Double { max(9, fontSize - 2) }
    public var footnoteFontSize: Double { max(8, fontSize - 3) }
}

/// The values worth remembering across launches. The screen limits aren't
/// among them: the display can change between runs, so they're supplied fresh.
public struct StoredAppearance: Equatable, Sendable {
    public var fontSize: Double
    public var chatWidth: Double
    public var chatHeight: Double
    public var appScale: AppScale

    public init(
        fontSize: Double = AppearanceSettings.defaultFontSize,
        chatWidth: Double = AppearanceSettings.defaultWidth,
        chatHeight: Double = AppearanceSettings.defaultHeight,
        appScale: AppScale = .medium
    ) {
        self.fontSize = fontSize
        self.chatWidth = chatWidth
        self.chatHeight = chatHeight
        self.appScale = appScale
    }
}

/// Remembers the choice across launches.
public protocol AppearanceStoring: AnyObject, Sendable {
    func load() -> StoredAppearance
    func save(_ appearance: StoredAppearance)
}

public final class UserDefaultsAppearanceStore: AppearanceStoring, @unchecked Sendable {
    private let fontKey = "appearance.fontSize"
    private let widthKey = "appearance.chatWidth"
    private let heightKey = "appearance.chatHeight"
    private let scaleKey = "appearance.appScale"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `object(forKey:)` rather than `double(forKey:)` so an unset key falls
    /// back to the default instead of to zero — which matters for width, added
    /// after the other two, and so absent for anyone upgrading. An unrecognised
    /// scale — written by a build with different steps — also falls back rather
    /// than throwing.
    public func load() -> StoredAppearance {
        StoredAppearance(
            fontSize: (defaults.object(forKey: fontKey) as? Double) ?? AppearanceSettings.defaultFontSize,
            chatWidth: (defaults.object(forKey: widthKey) as? Double) ?? AppearanceSettings.defaultWidth,
            chatHeight: (defaults.object(forKey: heightKey) as? Double) ?? AppearanceSettings.defaultHeight,
            appScale: (defaults.string(forKey: scaleKey).flatMap(AppScale.init(rawValue:))) ?? .medium
        )
    }

    public func save(_ appearance: StoredAppearance) {
        defaults.set(appearance.fontSize, forKey: fontKey)
        defaults.set(appearance.chatWidth, forKey: widthKey)
        defaults.set(appearance.chatHeight, forKey: heightKey)
        defaults.set(appearance.appScale.rawValue, forKey: scaleKey)
    }
}

public final class InMemoryAppearanceStore: AppearanceStoring, @unchecked Sendable {
    private var stored: StoredAppearance

    public init(_ stored: StoredAppearance = StoredAppearance()) {
        self.stored = stored
    }

    public func load() -> StoredAppearance { stored }

    public func save(_ appearance: StoredAppearance) { stored = appearance }
}
