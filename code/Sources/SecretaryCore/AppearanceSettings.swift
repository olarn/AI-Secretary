import Foundation

/// Text size and chat-window height.
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

    public private(set) var fontSize: Double
    public private(set) var chatHeight: Double

    /// Tallest the bubble may become: the usable height of the screen it's on.
    /// Deliberately not persisted — the display can change between launches, so
    /// this is supplied each time rather than remembered.
    public private(set) var maxHeight: Double

    public init(
        fontSize: Double = Self.defaultFontSize,
        chatHeight: Double = Self.defaultHeight,
        maxHeight: Double = Self.defaultHeight
    ) {
        self.fontSize = min(max(fontSize, Self.minFontSize), Self.maxFontSize)
        self.maxHeight = max(maxHeight, Self.defaultHeight)
        self.chatHeight = min(max(chatHeight, Self.defaultHeight), self.maxHeight)
    }

    /// Called when the screen is known or changes. Re-clamps the current height,
    /// so moving to a smaller display pulls an over-tall window back in.
    public mutating func setMaxHeight(_ height: Double) {
        maxHeight = max(height, Self.defaultHeight)
        chatHeight = min(chatHeight, maxHeight)
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

/// Remembers the choice across launches.
public protocol AppearanceStoring: AnyObject, Sendable {
    /// Only the two chosen numbers; the screen limit is applied separately.
    func load() -> (fontSize: Double, chatHeight: Double)
    func save(fontSize: Double, chatHeight: Double)
}

public final class UserDefaultsAppearanceStore: AppearanceStoring, @unchecked Sendable {
    private let fontKey = "appearance.fontSize"
    private let heightKey = "appearance.chatHeight"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `object(forKey:)` rather than `double(forKey:)` so an unset key falls
    /// back to the default instead of to zero.
    public func load() -> (fontSize: Double, chatHeight: Double) {
        (
            (defaults.object(forKey: fontKey) as? Double) ?? AppearanceSettings.defaultFontSize,
            (defaults.object(forKey: heightKey) as? Double) ?? AppearanceSettings.defaultHeight
        )
    }

    public func save(fontSize: Double, chatHeight: Double) {
        defaults.set(fontSize, forKey: fontKey)
        defaults.set(chatHeight, forKey: heightKey)
    }
}

public final class InMemoryAppearanceStore: AppearanceStoring, @unchecked Sendable {
    private var fontSize: Double
    private var chatHeight: Double

    public init(
        fontSize: Double = AppearanceSettings.defaultFontSize,
        chatHeight: Double = AppearanceSettings.defaultHeight
    ) {
        self.fontSize = fontSize
        self.chatHeight = chatHeight
    }

    public func load() -> (fontSize: Double, chatHeight: Double) { (fontSize, chatHeight) }

    public func save(fontSize: Double, chatHeight: Double) {
        self.fontSize = fontSize
        self.chatHeight = chatHeight
    }
}
