import Foundation

/// Which set of colours the windows are painted with.
///
/// Three, not a full theme engine: the charter asks for a small MVP, and the
/// problem being solved is one specific failure — a bright desktop showing
/// through the panel — not "I want to pick colours".
///
/// The three are the two palettes plus "follow the system", which is the whole
/// choice there is to make once the surfaces are opaque. A fourth, `contrast`
/// — dark with a heavier border — shipped in 0.10.197 and was taken out in
/// 0.10.198 at the owner's request. A stored `"contrast"` no longer decodes and
/// falls back to `system`, which is the same handling an unknown value gets.
public enum ThemeChoice: String, CaseIterable, Sendable, Codable {
    /// Follow the system's light/dark setting.
    case system
    /// Light whatever the system says.
    case light
    /// Dark whatever the system says. For a light desktop the user doesn't
    /// want to change.
    case dark

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// What the row in Settings says under the name.
    public var explanation: String {
        switch self {
        case .system: return "Follows macOS"
        case .light: return "Always light"
        case .dark: return "Always dark"
        }
    }
}

/// A colour as three components, not a `SwiftUI.Color`.
///
/// Components rather than a platform type for one reason: a test has to be able
/// to do arithmetic on it. `Color` can be compared but not measured, and the
/// thing worth checking about a palette is whether the text stands off its
/// background by enough — which is a number, computed from the components.
public struct ThemeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// WCAG relative luminance, on the sRGB components as stored.
    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

/// How far apart two colours are, 1 (identical) to 21 (black on white).
///
/// The usual floor for body text is 4.5. `Palette.contrastFloor` is what this
/// app holds itself to, and `ThemeTests` checks every pair against it.
public func contrastRatio(_ one: ThemeColor, _ other: ThemeColor) -> Double {
    let lighter = max(one.relativeLuminance, other.relativeLuminance)
    let darker = min(one.relativeLuminance, other.relativeLuminance)
    return (lighter + 0.05) / (darker + 0.05)
}

/// Every colour the windows use, named by the job it does rather than by what
/// it looks like.
///
/// **Opaque grounds, deliberately.** The panel used to be `.regularMaterial`,
/// which samples the desktop behind it: on a bright wallpaper the surface
/// lightened, and since every bubble was a low-opacity tint *over that surface*
/// the whole low-contrast layer — muted text, the bubble's edge, the small
/// chips — went with it. Whether the app was readable depended on the user's
/// wallpaper, which the app does not control. Grounds here are solid, so it
/// no longer does.
///
/// **Roles, not literals.** These live in `SecretaryCore` rather than in the
/// views for the reason `MessageBubbleStyle` does: `AISecretaryApp` is never
/// linked into the test bundle, so a colour decided there cannot be checked.
/// The view applies a role; it does not choose a value.
public struct Palette: Equatable, Sendable {

    /// The contrast every text colour must reach against every ground it can
    /// be drawn on. WCAG AA for body text.
    public static let contrastFloor: Double = 4.5

    // Grounds — surfaces something is drawn on top of.

    /// The window itself.
    public let ground: ThemeColor
    /// Small raised surfaces: the message box, chips, inline code.
    public let chipFill: ThemeColor
    /// The user's own messages.
    public let bubbleMine: ThemeColor
    /// The Secretary's messages.
    public let bubbleTheirs: ThemeColor
    /// A tinted card or pill that means "this is the active/primary thing".
    public let accentFill: ThemeColor
    /// A tinted card or pill that means "careful". Also the failure bubble:
    /// a turn that ended in an error is the same claim in bubble form, and
    /// giving it a fourth near-identical orange would be a distinction the eye
    /// can't make.
    public let warningFill: ThemeColor
    /// "This leaves the machine" — the strongest of the three.
    public let dangerFill: ThemeColor
    /// A neutral informational card.
    public let infoFill: ThemeColor
    /// A surface *inside* a bubble — a code block, a table.
    ///
    /// It cannot be told apart from its parent by fill alone: `bubbleMine` is a
    /// blue tint, `bubbleTheirs` a grey one, and one neutral cannot stand off
    /// both while staying a quiet surface. So the rule is that a nested surface
    /// is told apart by its **edge**: it always carries the hairline.
    ///
    /// Four sites, and every one of them must keep its stroke —
    /// `ChatPanelView.codeBlockView` / `.tableView` and
    /// `MarkdownBodyView`'s two. Two of them shipped without one for an hour;
    /// `nestedFill` against `bubbleMine` is 1.05 in `light` — no boundary at
    /// all without the stroke. `testEveryEdgeIsVisibleAgainstEveryGround` checks
    /// the hairline's *colour* would be visible — it cannot see whether the
    /// stroke is drawn, so that part is on the reader.
    public let nestedFill: ThemeColor

    // Marks — text, icons, and strokes drawn on those grounds.

    public let primaryText: ThemeColor
    /// Timestamps, the running commentary, hints. This is the role the old
    /// translucent background actually broke.
    public let mutedText: ThemeColor
    public let accent: ThemeColor
    public let warning: ThemeColor
    public let danger: ThemeColor
    public let success: ThemeColor
    public let info: ThemeColor

    /// Text and glyphs drawn *on* `accent` used as a solid fill — the selected
    /// footer button. The only role whose job is defined by another role, so
    /// the pair is checked together rather than against the grounds.
    public let onAccent: ThemeColor

    /// Separators and the outline of small controls.
    public let hairline: ThemeColor
    /// The outline of the speech bubble itself.
    public let panelBorder: ThemeColor
    public let panelBorderWidth: Double

    /// Whether the window should ask AppKit for the dark control appearance,
    /// so scrollers, the caret and the text-selection tint match the palette
    /// instead of the system setting.
    public let prefersDarkControls: Bool

    /// The grounds, paired with the name a failing test should print.
    ///
    /// A list rather than a `switch`: adding a ground is adding an element, and
    /// the contrast test then covers it without being edited.
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

    /// The marks that carry words. `hairline` and `panelBorder` are not here:
    /// they are edges, and an edge is allowed to be quieter than text.
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

    /// Used when the system is in light mode and the user hasn't overridden it.
    /// Still opaque — a light window that stays the same white over any
    /// wallpaper is the point, not the absence of light mode.
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

    /// Every palette that can end up on screen, so a check written once covers
    /// all of them — including any added later.
    public static let all: [(String, Palette)] = [
        ("light", .light),
        ("dark", .dark),
    ]
}

/// Which palette to paint with.
///
/// Takes the system's setting as an argument rather than reading it, so it is
/// the same function in a test as in the app.
public func palette(for choice: ThemeChoice, systemIsDark: Bool) -> Palette {
    switch choice {
    case .system: return systemIsDark ? .dark : .light
    case .light: return .light
    case .dark: return .dark
    }
}
