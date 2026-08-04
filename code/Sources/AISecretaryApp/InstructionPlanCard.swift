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
    let plan: InstructionPlan
    let risks: [InstructionRisk]
    let changedSinceLastRun: Bool
    let start: () -> Void
    let cancel: () -> Void

    /// Ticked by hand when something was flagged. The extra click is the whole
    /// point: a warning that sits beside an already-enabled button is a warning
    /// nobody has to have read.
    @State private var acknowledged = false

    private var needsAcknowledgement: Bool { !risks.isEmpty }
    private var canStart: Bool { !needsAcknowledgement || acknowledged }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Run these steps?", systemImage: "list.bullet.rectangle")
                .font(.caption.bold())

            Text(plan.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            if changedSinceLastRun {
                Label(
                    "The steps in this file have changed since you last ran it.",
                    systemImage: "pencil.circle"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(index + 1).")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(step)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !risks.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(risks) { risk in
                        // The words that triggered it, not just the verdict:
                        // a warning you can check is a warning you can weigh.
                        Text("⚠ \(risk.reason) — \(risk.evidence)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("I've read these and want to go ahead", isOn: $acknowledged)
                        .toggleStyle(.checkbox)
                        .font(.caption2)
                }
            }

            HStack(spacing: 8) {
                Button("Start") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)
                Button("Cancel") { cancel() }
                    .buttonStyle(.bordered)
            }
            .font(.caption)
        }
        .padding(10)
        .background(
            (risks.isEmpty ? Color.accentColor : Color.red).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
