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

    /// The same colour for the parts of a window SwiftUI does not paint — the
    /// title bar, and the ground behind a hosting view.
    ///
    /// Built from the stored sRGB components rather than from a system colour,
    /// and that is load-bearing: a dynamic `NSColor` resolves against the
    /// window's effective appearance, and resolving is how the system's
    /// light/dark setting gets back in after a character has chosen otherwise.
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


/// The ground under an opened Settings/Profile/Projects/Skills box — one view
/// so the four boxes cannot drift apart. Solid `chipFill` normally; in glass
/// mode the same colour as a `glassEffect` tint, which keeps the surface
/// defined enough for the small `mutedText` hints while letting the desktop
/// glow through. Tinted, not plain `.regular`: these boxes carry the smallest
/// text in the app, and an untinted pane's brightness is whatever the
/// wallpaper says it is.
struct PanelBoxGround: View {
    let palette: Palette
    let liquidGlass: Bool

    var body: some View {
        if liquidGlass {
            Color.clear.glassEffect(
                .regular.tint(palette.chipFill.color),
                in: RoundedRectangle(cornerRadius: 8)
            )
        } else {
            RoundedRectangle(cornerRadius: 8).fill(palette.chipFill.color)
        }
    }
}
