import SwiftUI
import AssistantState

/// Placeholder character representation (no production art yet).
/// Its color/symbol reflects the current AssistantState; tapping it
/// opens the chat/task panel.
struct CharacterView: View {
    let machine: AssistantStateMachine
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color(for: machine.state))
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: symbol(for: machine.state))
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                )
                .shadow(radius: 6)

            Text(machine.state.description.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func color(for state: AssistantState) -> Color {
        switch state {
        case .idle: return .gray
        case .listening: return .blue
        case .thinking: return .purple
        case .working: return .orange
        case .success: return .green
        case .error: return .red
        }
    }

    private func symbol(for state: AssistantState) -> String {
        switch state {
        case .idle: return "moon.zzz"
        case .listening: return "ear"
        case .thinking: return "brain"
        case .working: return "gearshape.2"
        case .success: return "checkmark"
        case .error: return "exclamationmark.triangle"
        }
    }
}
