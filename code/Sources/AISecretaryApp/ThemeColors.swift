import AppKit
import SwiftUI
import SecretaryCore

extension ThemeColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    func color(opacity: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

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
    func themedWindow(_ palette: Palette) -> some View {
        self
            .environment(\.palette, palette)
            .foregroundStyle(palette.primaryText.color)
            .tint(palette.accent.color)
            .background(palette.ground.color)
    }
}

extension Palette {
    var controlAppearance: NSAppearance? {
        NSAppearance(named: prefersDarkControls ? .darkAqua : .aqua)
    }
}

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
