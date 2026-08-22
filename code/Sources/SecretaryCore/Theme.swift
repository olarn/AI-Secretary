import Foundation

public enum ThemeChoice: String, CaseIterable, Sendable, Codable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var explanation: String {
        switch self {
        case .system: return "Follows macOS"
        case .light: return "Always light"
        case .dark: return "Always dark"
        }
    }
}

public struct ThemeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

public func contrastRatio(_ one: ThemeColor, _ other: ThemeColor) -> Double {
    let lighter = max(one.relativeLuminance, other.relativeLuminance)
    let darker = min(one.relativeLuminance, other.relativeLuminance)
    return (lighter + 0.05) / (darker + 0.05)
}

public struct Palette: Equatable, Sendable {

    public static let contrastFloor: Double = 4.5

    public let ground: ThemeColor
    public let chipFill: ThemeColor
    public let bubbleMine: ThemeColor
    public let bubbleTheirs: ThemeColor
    public let accentFill: ThemeColor
    public let warningFill: ThemeColor
    public let dangerFill: ThemeColor
    public let infoFill: ThemeColor
    public let nestedFill: ThemeColor

    public let primaryText: ThemeColor
    public let mutedText: ThemeColor
    public let accent: ThemeColor
    public let warning: ThemeColor
    public let danger: ThemeColor
    public let success: ThemeColor
    public let info: ThemeColor

    public let onAccent: ThemeColor

    public let hairline: ThemeColor
    public let panelBorder: ThemeColor
    public let panelBorderWidth: Double

    public let prefersDarkControls: Bool

    public static let groundRoles: [(String, KeyPath<Palette, ThemeColor>)] = [
        ("ground", \.ground),
        ("chipFill", \.chipFill),
        ("bubbleMine", \.bubbleMine),
        ("bubbleTheirs", \.bubbleTheirs),
        ("accentFill", \.accentFill),
        ("warningFill", \.warningFill),
        ("dangerFill", \.dangerFill),
        ("infoFill", \.infoFill),
        ("nestedFill", \.nestedFill),
    ]

    public static let textRoles: [(String, KeyPath<Palette, ThemeColor>)] = [
        ("primaryText", \.primaryText),
        ("mutedText", \.mutedText),
        ("accent", \.accent),
        ("warning", \.warning),
        ("danger", \.danger),
        ("success", \.success),
        ("info", \.info),
    ]
}

extension Palette {

    public static let light = Palette(
        ground: ThemeColor(0.99, 0.99, 1.00),
        chipFill: ThemeColor(0.93, 0.935, 0.95),
        bubbleMine: ThemeColor(0.88, 0.91, 0.99),
        bubbleTheirs: ThemeColor(0.94, 0.945, 0.955),
        accentFill: ThemeColor(0.86, 0.90, 0.99),
        warningFill: ThemeColor(0.99, 0.91, 0.82),
        dangerFill: ThemeColor(0.99, 0.89, 0.88),
        infoFill: ThemeColor(0.86, 0.95, 0.96),
        nestedFill: ThemeColor(0.87, 0.875, 0.89),
        primaryText: ThemeColor(0.08, 0.09, 0.11),
        mutedText: ThemeColor(0.36, 0.37, 0.40),
        accent: ThemeColor(0.13, 0.34, 0.80),
        warning: ThemeColor(0.54, 0.31, 0.02),
        danger: ThemeColor(0.72, 0.13, 0.10),
        success: ThemeColor(0.08, 0.44, 0.18),
        info: ThemeColor(0.06, 0.40, 0.45),
        onAccent: ThemeColor(1.00, 1.00, 1.00),
        hairline: ThemeColor(0.74, 0.75, 0.78),
        panelBorder: ThemeColor(0.62, 0.63, 0.67),
        panelBorderWidth: 1.5,
        prefersDarkControls: false
    )

    public static let dark = Palette(
        ground: ThemeColor(0.11, 0.115, 0.13),
        chipFill: ThemeColor(0.17, 0.175, 0.195),
        bubbleMine: ThemeColor(0.17, 0.22, 0.32),
        bubbleTheirs: ThemeColor(0.16, 0.165, 0.185),
        accentFill: ThemeColor(0.19, 0.25, 0.38),
        warningFill: ThemeColor(0.28, 0.22, 0.11),
        dangerFill: ThemeColor(0.30, 0.17, 0.16),
        infoFill: ThemeColor(0.13, 0.25, 0.26),
        nestedFill: ThemeColor(0.06, 0.065, 0.08),
        primaryText: ThemeColor(0.95, 0.95, 0.96),
        mutedText: ThemeColor(0.70, 0.71, 0.74),
        accent: ThemeColor(0.55, 0.72, 1.00),
        warning: ThemeColor(0.98, 0.75, 0.40),
        danger: ThemeColor(1.00, 0.55, 0.50),
        success: ThemeColor(0.50, 0.88, 0.58),
        info: ThemeColor(0.45, 0.85, 0.87),
        onAccent: ThemeColor(0.06, 0.08, 0.14),
        hairline: ThemeColor(0.32, 0.33, 0.36),
        panelBorder: ThemeColor(0.42, 0.43, 0.47),
        panelBorderWidth: 1.5,
        prefersDarkControls: true
    )

    public static let all: [(String, Palette)] = [
        ("light", .light),
        ("dark", .dark),
    ]
}

public func palette(for choice: ThemeChoice, systemIsDark: Bool) -> Palette {
    switch choice {
    case .system: return systemIsDark ? .dark : .light
    case .light: return .light
    case .dark: return .dark
    }
}
