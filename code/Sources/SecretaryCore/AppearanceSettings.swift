import FunctionalCore
import Foundation

/// How big the floating character is on the desktop: three fixed steps, both
/// measured from the current size so they can't compound.
public enum CharacterScale: String, CaseIterable, Sendable, Codable {
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
    public var characterScale: CharacterScale
    /// Which colours the windows are painted with. Not clamped to anything —
    /// unlike the sizes, every value is as valid as every other.
    public var theme: ThemeChoice

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
        characterScale: CharacterScale = .medium,
        theme: ThemeChoice = .system
    ) {
        self.characterScale = characterScale
        self.theme = theme
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
    public var nextWiderWidth: Option<Double> {
        Option.fromOptional(widthStops.first { $0 > chatWidth })
    }

    public var canWiden: Bool { nextWiderWidth.isDefined }
    /// Restoring is one press back to the default, not a step, so it's offered
    /// from any width above the default — including one dragged by hand.
    public var canRestoreWidth: Bool { chatWidth > Self.defaultWidth }

    public mutating func widenChat() {
        chatWidth = nextWiderWidth.getOrElse(chatWidth)
    }

    /// Straight back to the default width in one press. Widening is a stepped
    /// climb because each step is a size worth stopping at; coming back is not —
    /// what's wanted there is the bubble out of the way, now.
    public mutating func restoreChatWidth() {
        chatWidth = min(Self.defaultWidth, maxWidth)
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
    /// The explanatory line under a control — "Stored only in your Keychain",
    /// "Blank means professional". Smaller than the row it explains, and
    /// scaled like everything else: these were pinned at 9pt, so the Settings
    /// and Profile panels stayed the same size whatever the text size said.
    public var hintFontSize: Double { max(8, fontSize - 5) }

    /// Gap between rows inside a panel, and the panel's own inset.
    ///
    /// Scaled for the same reason the text is, and learned the same way: type
    /// that grew while the spacing stayed at 6 and 10 points made the Settings
    /// panel read as a wall — "พอขยาย font แล้ว เนื้อหามันแน่น". Rhythm is part
    /// of the size, not a constant the size happens to sit inside.
    public var panelSpacing: Double { max(4, fontSize * 0.45) }
    public var panelPadding: Double { max(8, fontSize * 0.75) }
}

/// The values worth remembering across launches. The screen limits aren't
/// among them: the display can change between runs, so they're supplied fresh.
public struct StoredAppearance: Equatable, Sendable {
    public var fontSize: Double
    public var chatWidth: Double
    public var chatHeight: Double
    public var characterScale: CharacterScale
    public var theme: ThemeChoice

    public init(
        fontSize: Double = AppearanceSettings.defaultFontSize,
        chatWidth: Double = AppearanceSettings.defaultWidth,
        chatHeight: Double = AppearanceSettings.defaultHeight,
        characterScale: CharacterScale = .medium,
        theme: ThemeChoice = .system
    ) {
        self.fontSize = fontSize
        self.chatWidth = chatWidth
        self.chatHeight = chatHeight
        self.characterScale = characterScale
        self.theme = theme
    }
}

/// Remembers the choice across launches.
public protocol AppearanceStoring: AnyObject, Sendable {
    func load() -> StoredAppearance
    func save(_ appearance: StoredAppearance)
}

public final class UserDefaultsAppearanceStore: AppearanceStoring, @unchecked Sendable {
    // The names on disk, unchanged. `appScale` reads oddly now that the type is
    // `CharacterScale`, and renaming it would quietly discard the S/M/L choice
    // of everyone who had made one — a key is a promise to whatever wrote it.
    private static let settingNames = (
        font: "fontSize",
        width: "chatWidth",
        height: "chatHeight",
        scale: "appScale",
        theme: "theme"
    )
    private let defaults: UserDefaults
    private let character: UUID?

    /// - Parameter character: whose look this is. `nil` means the app-wide keys
    ///   written before each character had her own, which every character still
    ///   reads as her starting point — see `load`.
    public init(defaults: UserDefaults = .standard, character: UUID? = nil) {
        self.defaults = defaults
        self.character = character
    }

    private func key(_ setting: String) -> String {
        appearanceKey(setting, character: character)
    }

    /// Her own value, or the shared one, or the default.
    ///
    /// The middle step is what keeps the app looking the way it did: nothing is
    /// renamed or moved when characters get their own settings, so on the first
    /// launch after this every character reads the one look that was there and
    /// they all match. She stops reading it the moment she is changed, because
    /// from then on she has a value of her own.
    private func read<T>(_ setting: String, _ decode: (Any) -> T?) -> T? {
        let mine = character.flatMap { _ in defaults.object(forKey: key(setting)) }
        let shared = defaults.object(forKey: appearanceKey(setting, character: nil))
        return (mine ?? shared).flatMap(decode)
    }

    /// `object(forKey:)` rather than `double(forKey:)` so an unset key falls
    /// back to the default instead of to zero — which matters for width, added
    /// after the other two, and so absent for anyone upgrading. An unrecognised
    /// scale — written by a build with different steps — also falls back rather
    /// than throwing.
    public func load() -> StoredAppearance {
        let names = Self.settingNames
        return StoredAppearance(
            fontSize: read(names.font) { $0 as? Double } ?? AppearanceSettings.defaultFontSize,
            chatWidth: read(names.width) { $0 as? Double } ?? AppearanceSettings.defaultWidth,
            chatHeight: read(names.height) { $0 as? Double } ?? AppearanceSettings.defaultHeight,
            characterScale: read(names.scale) { ($0 as? String).flatMap(CharacterScale.init(rawValue:)) } ?? .medium,
            theme: read(names.theme) { ($0 as? String).flatMap(ThemeChoice.init(rawValue:)) } ?? .system
        )
    }

    /// Writes only under this character's keys. The shared ones are left where
    /// they are: they are what a character who has never been changed is still
    /// reading, and overwriting them with one character's choice would move
    /// everybody who hasn't chosen yet.
    public func save(_ appearance: StoredAppearance) {
        let names = Self.settingNames
        defaults.set(appearance.fontSize, forKey: key(names.font))
        defaults.set(appearance.chatWidth, forKey: key(names.width))
        defaults.set(appearance.chatHeight, forKey: key(names.height))
        defaults.set(appearance.characterScale.rawValue, forKey: key(names.scale))
        defaults.set(appearance.theme.rawValue, forKey: key(names.theme))
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
