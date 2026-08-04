import SwiftUI

/// The Projects / Profile / Skills / Settings buttons, and whether one is open.
///
/// It exists for one reason: AppKit strips the accent colour from a tinted
/// control whenever its window isn't key. Reasonable for an ordinary app, wrong
/// for this one, because this window is *designed* never to take focus. The
/// result was a pane sitting open with nothing in the footer saying so — open
/// Projects, then click anything else (the Add Project dialog, Finder, a
/// browser) and the button went grey while the pane stayed exactly where it
/// was. A fill we draw ourselves stays put whether or not the app is frontmost,
/// which is the only honest way to answer "is a panel open?" in a window that
/// spends its life in the background.
///
/// Everything else is deliberately still `.bordered` with the same control
/// size: the first attempt drew the whole button by hand and, because a plain
/// `Button` inherits the surrounding `.font` while `.toggleStyle(.button)`
/// quietly ignores it, the labels jumped to the chat's text size and wrapped
/// mid-word — "Projec / ts" at 28pt. Only the colour was meant to change.
struct PanelToggleStyle: ToggleStyle {
    let controlSize: ControlSize

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(.bordered)
        .controlSize(controlSize)
        // Behind the bezel rather than instead of it, so the metrics, corner
        // radius and hit area stay exactly what the bordered style gives every
        // other button in the row.
        .background(
            configuration.isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .foregroundStyle(configuration.isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
    }
}
