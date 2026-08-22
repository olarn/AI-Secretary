import SwiftUI
import SecretaryCore

struct InstructionPlanCard: View {
    @Environment(\.palette) private var theme

    let plan: InstructionPlan
    let risks: [InstructionRisk]
    let changedSinceLastRun: Bool
    let fontSize: Double
    let hintSize: Double
    let spacing: Double
    let padding: Double
    let start: () -> Void
    let cancel: () -> Void

    @State private var acknowledged = false

    private var needsAcknowledgement: Bool { !risks.isEmpty }
    private var canStart: Bool { !needsAcknowledgement || acknowledged }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Label("Run these steps?", systemImage: "list.bullet.rectangle")
                .font(.system(size: fontSize, weight: .semibold))

            Text(plan.relativePath)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(theme.mutedText.color)

            if changedSinceLastRun {
                Label(
                    "The steps in this file have changed since you last ran it.",
                    systemImage: "pencil.circle"
                )
                .font(.system(size: hintSize))
                .foregroundStyle(theme.warning.color)
            }

            VStack(alignment: .leading, spacing: spacing * 0.5) {
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: spacing * 0.8) {
                        Text("\(index + 1).")
                            .font(.system(size: hintSize, design: .monospaced))
                            .foregroundStyle(theme.mutedText.color)
                        Text(step)
                            .font(.system(size: fontSize))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !risks.isEmpty {
                VStack(alignment: .leading, spacing: spacing * 0.5) {
                    ForEach(risks) { risk in
                        Text("⚠ \(risk.reason) — \(risk.evidence)")
                            .font(.system(size: hintSize))
                            .foregroundStyle(theme.danger.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("I've read these and want to go ahead", isOn: $acknowledged)
                        .toggleStyle(.checkbox)
                        .font(.system(size: hintSize))
                }
            }

            HStack(spacing: spacing * 1.3) {
                Button(CardChoice.start) { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)
                Button(CardChoice.cancel) { cancel() }
                    .buttonStyle(.bordered)
            }
            .font(.system(size: fontSize))
        }
        .padding(padding)
        .background(
            (risks.isEmpty ? theme.accentFill : theme.dangerFill).color,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
