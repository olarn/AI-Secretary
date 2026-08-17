import SwiftUI
import SecretaryCore

/// The steps read out of an instruction file, shown in full before any of them
/// runs.
///
/// This card *is* the safety of the feature. Everything else — the untrusted
/// framing in the prompt, the pattern scan, the per-action permission cards —
/// supports it; none of it replaces someone reading the list and saying yes.
/// So the steps are shown verbatim, in order, with no summarising and no
/// scrolling past: what the app is about to do fits on the screen or the file
/// is too big to run blind.
///
/// It decides nothing. Whether there are risks, and whether the file changed,
/// are answered in `SecretaryCore`; this only renders the answers and calls
/// back.
struct InstructionPlanCard: View {
    /// The colours in force, set by whichever window this view is inside.
    @Environment(\.palette) private var theme

    let plan: InstructionPlan
    let risks: [InstructionRisk]
    let changedSinceLastRun: Bool
    /// Sizes come from the app's text setting, like everything else the
    /// person reads — a card pinned at 11pt beside 28pt replies is the same
    /// bug the panels had.
    let fontSize: Double
    let hintSize: Double
    let spacing: Double
    let padding: Double
    let start: () -> Void
    let cancel: () -> Void

    /// Ticked by hand when something was flagged. The extra click is the whole
    /// point: a warning that sits beside an already-enabled button is a warning
    /// nobody has to have read.
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
                        // The words that triggered it, not just the verdict:
                        // a warning you can check is a warning you can weigh.
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
