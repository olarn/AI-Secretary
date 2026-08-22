import FunctionalCore
import Foundation

public enum CharacterScale: String, CaseIterable, Sendable, Codable {
    case small, medium, large

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

public struct AppearanceSettings: Equatable, Sendable {
    public static let minFontSize: Double = 10
    public static let maxFontSize: Double = 32
    public static let fontStep: Double = 2
    public static let defaultFontSize: Double = 12

    public static let defaultHeight: Double = 520
    public static let heightStep: Double = 60

    public static let defaultWidth: Double = 360
    public static let widthFactors: [Double] = [1, 2, 3]

    public private(set) var fontSize: Double
    public private(set) var chatWidth: Double
    public private(set) var chatHeight: Double
    public var characterScale: CharacterScale
    public var theme: ThemeChoice
    public var font: FontChoice
    public var liquidGlass: Bool

    public private(set) var maxHeight: Double
    public private(set) var maxWidth: Double

    public init(
        fontSize: Double = Self.defaultFontSize,
        chatWidth: Double = Self.defaultWidth,
        chatHeight: Double = Self.defaultHeight,
        maxWidth: Double = Self.defaultWidth,
        maxHeight: Double = Self.defaultHeight,
        characterScale: CharacterScale = .medium,
        theme: ThemeChoice = .system,
        font: FontChoice = .system,
        liquidGlass: Bool = false
    ) {
        self.characterScale = characterScale
        self.theme = theme
        self.font = font
        self.liquidGlass = liquidGlass
        self.fontSize = min(max(fontSize, Self.minFontSize), Self.maxFontSize)
        self.maxHeight = max(maxHeight, Self.defaultHeight)
        self.maxWidth = max(maxWidth, Self.defaultWidth)
        self.chatHeight = min(max(chatHeight, Self.defaultHeight), self.maxHeight)
        self.chatWidth = min(max(chatWidth, Self.defaultWidth), self.maxWidth)
    }

    public mutating func setMaxHeight(_ height: Double) {
        maxHeight = max(height, Self.defaultHeight)
        chatHeight = min(chatHeight, maxHeight)
    }

    public mutating func setMaxWidth(_ width: Double) {
        maxWidth = max(width, Self.defaultWidth)
        chatWidth = min(chatWidth, maxWidth)
    }

    public mutating func setChatSize(width: Double, height: Double) {
        chatWidth = min(max(width, Self.defaultWidth), maxWidth)
        chatHeight = min(max(height, Self.defaultHeight), maxHeight)
    }

    public var widthStops: [Double] {
        var stops: [Double] = []
        for factor in Self.widthFactors {
            let stop = min(Self.defaultWidth * factor, maxWidth)
            if stops.last != stop { stops.append(stop) }
        }
        return stops
    }

    public var nextWiderWidth: Option<Double> {
        Option.fromOptional(widthStops.first { $0 > chatWidth })
    }

    public var canWiden: Bool { nextWiderWidth.isDefined }
    public var canRestoreWidth: Bool { chatWidth > Self.defaultWidth }

    public mutating func widenChat() {
        chatWidth = nextWiderWidth.getOrElse(chatWidth)
    }

    public mutating func restoreChatWidth() {
        chatWidth = min(Self.defaultWidth, maxWidth)
    }

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

    public var canIncreaseFontSize: Bool { fontSize < Self.maxFontSize }
    public var canDecreaseFontSize: Bool { fontSize > Self.minFontSize }
    public var canIncreaseHeight: Bool { chatHeight < maxHeight }
    public var canDecreaseHeight: Bool { chatHeight > Self.defaultHeight }

    public var metrics: TextMetrics { TextMetrics(fontSize: fontSize) }

    public var secondaryFontSize: Double { metrics.secondaryFontSize }
    public var footnoteFontSize: Double { metrics.footnoteFontSize }
    public var captionFontSize: Double { metrics.captionFontSize }
    public var hintFontSize: Double { metrics.hintFontSize }
    public var panelSpacing: Double { metrics.panelSpacing }
    public var panelPadding: Double { metrics.panelPadding }
}

public struct TextMetrics: Equatable, Sendable {
    public let fontSize: Double

    public init(fontSize: Double) {
        self.fontSize = fontSize
    }

    public var secondaryFontSize: Double { max(9, fontSize - 2) }
    public var footnoteFontSize: Double { max(8, fontSize - 3) }
    public var captionFontSize: Double { max(9, secondaryFontSize - 2) }
    public var hintFontSize: Double { max(8, fontSize - 5) }

    public var panelSpacing: Double { max(4, fontSize * 0.45) }
    public var panelPadding: Double { max(8, fontSize * 0.75) }
}

public struct StoredAppearance: Equatable, Sendable {
    public var fontSize: Double
    public var chatWidth: Double
    public var chatHeight: Double
    public var characterScale: CharacterScale
    public var theme: ThemeChoice
    public var font: FontChoice
    public var liquidGlass: Bool

    public init(
        fontSize: Double = AppearanceSettings.defaultFontSize,
        chatWidth: Double = AppearanceSettings.defaultWidth,
        chatHeight: Double = AppearanceSettings.defaultHeight,
        characterScale: CharacterScale = .medium,
        theme: ThemeChoice = .system,
        font: FontChoice = .system,
        liquidGlass: Bool = false
    ) {
        self.fontSize = fontSize
        self.chatWidth = chatWidth
        self.chatHeight = chatHeight
        self.characterScale = characterScale
        self.theme = theme
        self.font = font
        self.liquidGlass = liquidGlass
    }
}

public protocol AppearanceStoring: AnyObject, Sendable {
    func load() -> StoredAppearance
    func save(_ appearance: StoredAppearance)
}

public final class UserDefaultsAppearanceStore: AppearanceStoring, @unchecked Sendable {
    private static let settingNames = (
        font: "fontSize",
        width: "chatWidth",
        height: "chatHeight",
        scale: "appScale",
        theme: "theme",
        fontDesign: "fontDesign",
        liquidGlass: "liquidGlass"
    )
    private let defaults: UserDefaults
    private let character: UUID?

    public init(defaults: UserDefaults = .standard, character: UUID? = nil) {
        self.defaults = defaults
        self.character = character
    }

    private func key(_ setting: String) -> String {
        appearanceKey(setting, character: character)
    }

    private func read<T>(_ setting: String, _ decode: (Any) -> T?) -> T? {
        let mine = character.flatMap { _ in defaults.object(forKey: key(setting)) }
        let shared = defaults.object(forKey: appearanceKey(setting, character: nil))
        return (mine ?? shared).flatMap(decode)
    }

    public func load() -> StoredAppearance {
        let names = Self.settingNames
        return StoredAppearance(
            fontSize: read(names.font) { $0 as? Double } ?? AppearanceSettings.defaultFontSize,
            chatWidth: read(names.width) { $0 as? Double } ?? AppearanceSettings.defaultWidth,
            chatHeight: read(names.height) { $0 as? Double } ?? AppearanceSettings.defaultHeight,
            characterScale: read(names.scale) { ($0 as? String).flatMap(CharacterScale.init(rawValue:)) } ?? .medium,
            theme: read(names.theme) { ($0 as? String).flatMap(ThemeChoice.init(rawValue:)) } ?? .system,
            font: read(names.fontDesign) { ($0 as? String).flatMap(FontChoice.init(rawValue:)) } ?? .system,
            liquidGlass: read(names.liquidGlass) { $0 as? Bool } ?? false
        )
    }

    public func save(_ appearance: StoredAppearance) {
        let names = Self.settingNames
        defaults.set(appearance.fontSize, forKey: key(names.font))
        defaults.set(appearance.chatWidth, forKey: key(names.width))
        defaults.set(appearance.chatHeight, forKey: key(names.height))
        defaults.set(appearance.characterScale.rawValue, forKey: key(names.scale))
        defaults.set(appearance.theme.rawValue, forKey: key(names.theme))
        defaults.set(appearance.font.rawValue, forKey: key(names.fontDesign))
        defaults.set(appearance.liquidGlass, forKey: key(names.liquidGlass))
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
