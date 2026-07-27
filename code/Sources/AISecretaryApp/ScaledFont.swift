import SwiftUI
import SecretaryCore

/// Panel text sizes, all derived from the one number the user controls.
///
/// The +/- buttons are meant to resize *the panel*, not just the replies, so no
/// view here should carry a literal `.caption`/`.caption2`: those ignore the
/// setting entirely, which is exactly how the settings box, the composer and the
/// footer buttons ended up staying at 10pt beside 32pt answers.
///
/// Three steps cover the chrome — heading, label, hint — and the body size is
/// the transcript's own. The numbers are the sizes at the default 12pt body;
/// `scaled(_:)` moves them from there.
extension AppearanceSettings {

    /// The panel's own title — the secretary's name in the header.
    var titleFont: Font { .system(size: scaled(13), weight: .semibold) }

    /// A section heading inside the panel ("Settings", "Projects").
    var headingFont: Font { .system(size: scaled(11), weight: .bold) }

    /// Ordinary chrome: field text, button titles, row labels.
    var labelFont: Font { .system(size: scaled(10)) }

    /// Explanatory small print sitting under a control.
    var hintFont: Font { .system(size: scaled(9)) }

    /// The smallest thing that still has to be readable — inline status glyphs.
    var glyphFont: Font { .system(size: scaled(7)) }

    /// Reply text. Monospaced, matching `MessageTextView`.
    var bodyFont: Font { .system(size: fontSize, design: .monospaced) }

    /// Table cells. Deliberately the same face and size as `bodyFont`: at equal
    /// point sizes a proportional font reads noticeably smaller than the
    /// monospaced body around it, so a table set in the system font looked like
    /// it wasn't growing with the rest of the answer even though it was.
    func tableFont(bold: Bool) -> Font {
        .system(size: fontSize, weight: bold ? .bold : .regular, design: .monospaced)
    }

    /// Sizes for the pieces that aren't `Font` — an `NSFont`, or a fixed frame
    /// that has to keep pace with the text inside it.
    func size(_ base: Double) -> Double { scaled(base) }

    /// Bordered buttons and button-style toggles take their text size from the
    /// control size, not from `.font(_:)` — a `.mini` button stays 10pt however
    /// large the surrounding text is, which is why the footer toggles were the
    /// last thing left behind at 32pt. Stepping the control size instead is the
    /// supported way to make them grow, and it keeps the padding in proportion
    /// rather than putting big text in a small pill.
    /// For the small chrome toggles along the bottom, which are deliberately
    /// smaller than the panel's real buttons.
    var chromeControlSize: ControlSize {
        switch fontSize {
        case ..<16: return .mini
        case ..<22: return .small
        case ..<28: return .regular
        default: return .large
        }
    }

    /// For buttons that are part of the conversation — Approve, Deny, Save, Add
    /// project. Starts at `.regular`, which is what they have always been at the
    /// default text size, so turning the text up is the only thing that changes
    /// them.
    ///
    /// Capped at `.large` deliberately. The bubble is a fixed 360pt wide, and at
    /// `.extraLarge` a row like "Text size  32pt  −  +" no longer fits it: the
    /// buttons win the space and the label truncates to "Text s…". Past this
    /// point the text keeps growing and the controls stop.
    var controlSize: ControlSize {
        switch fontSize {
        case ..<16: return .regular
        default: return .large
        }
    }
}
