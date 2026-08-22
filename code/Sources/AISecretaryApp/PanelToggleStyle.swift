import SwiftUI
import SecretaryCore

struct PanelToggleStyle: ToggleStyle {
    let fontSize: Double
    let controlSize: ControlSize
    let palette: Palette
    let liquidGlass: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let button = Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.system(size: fontSize))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        if liquidGlass {
            Button {
                configuration.isOn.toggle()
            } label: {
                configuration.label
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, fontSize * 0.85)
                    .padding(.vertical, fontSize * 0.35)
            }
            .buttonStyle(.plain)
            .background(
                Color.clear.glassEffect(
                    configuration.isOn ? .regular.tint(palette.accentFill.color) : .regular,
                    in: Capsule()
                )
            )
            .contentShape(Capsule())
            .foregroundStyle(palette.primaryText.color)
        } else {
            button
                .buttonStyle(.bordered)
                .controlSize(controlSize)
                .background(stateFill(isOn: configuration.isOn), in: RoundedRectangle(cornerRadius: fontSize * 0.4))
                .foregroundStyle(labelColor(isOn: configuration.isOn))
                .tint(labelColor(isOn: configuration.isOn))
        }
    }

    private func stateFill(isOn: Bool) -> AnyShapeStyle {
        isOn ? AnyShapeStyle(palette.accent.color) : AnyShapeStyle(Color.clear)
    }

    private func labelColor(isOn: Bool) -> Color {
        isOn ? palette.onAccent.color : palette.primaryText.color
    }
}
