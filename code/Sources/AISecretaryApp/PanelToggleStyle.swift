import SwiftUI
import SecretaryCore

/// The Projects / Profile / Skills / Settings buttons: how big they are, and
/// which one is open.
///
/// Two things `.toggleStyle(.button)` got wrong, both of them quiet.
///
/// **The colour.** AppKit strips the accent from a tinted control whenever its
/// window isn't key. Reasonable for an ordinary app, wrong for this one, whose
/// window is *designed* never to take focus — so an open pane had nothing in
/// the footer saying so. Open Projects, then click the Add Project dialog, or
/// Finder, or a browser, and the button went grey while the pane stayed
/// exactly where it was. The fill is drawn here instead, and stays put whether
/// or not the app is frontmost, which is the only honest answer in a window
/// that spends its life in the background.
///
/// **The size.** That style also ignores the surrounding `.font`, so the
/// footer never actually grew with the app's text size — the row looked the
/// same at 10pt as at 28pt, which is what the old comment about "unreadable
/// specks next to 32pt replies" was trying to prevent and didn't. The label's
/// size is set explicitly here.
///
/// Growing has a limit the window imposes rather than a number picked here:
/// four labels plus their padding stop fitting a narrow panel somewhere above
/// 20pt, and the first attempt at this wrapped them mid-word — "Projec / ts".
/// So each label stays on one line and shrinks to fit instead. Widen the
/// window and they grow back.
struct PanelToggleStyle: ToggleStyle {
    let fontSize: Double
    let controlSize: ControlSize
    /// Passed in, not read from the environment: a `ToggleStyle` is not a
    /// `View`, so `@Environment` in one is never populated.
    let palette: Palette
    /// Glass mode swaps the accent fill for a neutral one: on glass chrome the
    /// state is said by the surface, not by colour (Liquid Glass rule #7), and
    /// `chipFill` stands off the glass in both palettes.
    let liquidGlass: Bool

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.system(size: fontSize))
                .lineLimit(1)
                // Never a broken word. Below this the label would be smaller
                // than the secondary text around it, at which point the row is
                // too cramped to read at all and shrinking further doesn't
                // help.
                .minimumScaleFactor(0.55)
        }
        .buttonStyle(.bordered)
        .controlSize(controlSize)
        // Behind the bezel rather than instead of it, so the corner radius and
        // hit area stay whatever the bordered style gives every other button
        // in the row.
        .background(stateFill(isOn: configuration.isOn), in: RoundedRectangle(cornerRadius: fontSize * 0.4))
        .foregroundStyle(labelColor(isOn: configuration.isOn))
        // `.tint`, not only `.foregroundStyle`: a bordered button takes its
        // label colour from the tint, so the foreground style alone left the
        // selected button's label the same blue as the fill drawn behind it —
        // a solid blue block with the word invisible inside it. Seen in the
        // running app; nothing about the code read wrong.
        .tint(labelColor(isOn: configuration.isOn))
    }

    private func stateFill(isOn: Bool) -> AnyShapeStyle {
        switch (liquidGlass, isOn) {
        case (true, true): AnyShapeStyle(palette.chipFill.color)
        case (true, false): AnyShapeStyle(Color.clear)
        case (false, true): AnyShapeStyle(palette.accent.color)
        case (false, false): AnyShapeStyle(Color.clear)
        }
    }

    /// On glass the open button's ground is `chipFill`, which `primaryText`
    /// already clears by the tested floor — `onAccent` only pairs with `accent`.
    private func labelColor(isOn: Bool) -> Color {
        isOn && !liquidGlass ? palette.onAccent.color : palette.primaryText.color
    }
}
