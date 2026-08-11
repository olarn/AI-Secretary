import AppKit
import SwiftUI
import SecretaryCore

/// The one place a `ThemeColor` becomes something AppKit or SwiftUI can draw.
///
/// The palette is components rather than `Color` so the test bundle can measure
/// it — `AISecretaryApp` is never linked into it, so a colour decided here
/// could not be checked at all. This file is the conversion and nothing else:
/// it makes no choices, so there is nothing in it to test.
extension ThemeColor {
    /// Explicitly sRGB. The default `Color(red:green:blue:)` is device RGB,
    /// which is not the space the contrast numbers were computed in.
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    func color(opacity: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

/// How the palette reaches a view that isn't handed the `Appearance` object.
///
/// The environment rather than a parameter threaded down: the colours are the
/// same for every view in a window, and a parameter on each of a dozen small
/// structs is a dozen chances to forget one — which shows up as a single row
/// still lit by the system's setting while everything around it is not.
///
/// Every window root sets it. The default is only there because
/// `EnvironmentKey` requires one.
private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .dark
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Paints a window: the palette for everything inside it, an opaque ground,
    /// and the default text and control tints so an unstyled `Text` added later
    /// still comes from the theme.
    func themedWindow(_ palette: Palette) -> some View {
        self
            .environment(\.palette, palette)
            .foregroundStyle(palette.primaryText.color)
            .tint(palette.accent.color)
            .background(palette.ground.color)
    }
}

extension Palette {
    /// What the window should ask AppKit for, so the caret, the scroller and
    /// the selection tint are lit the same way as everything drawn around them.
    var controlAppearance: NSAppearance? {
        NSAppearance(named: prefersDarkControls ? .darkAqua : .aqua)
    }
}
