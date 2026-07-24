import SwiftUI
import AssistantState

/// Desktop companion character. Displays the placeholder avatar plus a
/// small state badge; tapping it opens the chat/task panel.
struct CharacterView: View {
    let machine: AssistantStateMachine
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(stateColor(for: machine.state).opacity(0.25))
                    .frame(width: 100, height: 100)

                MikuAvatarView()

                StatusBadge(state: machine.state)
                    .offset(x: 4, y: 4)
            }
            .shadow(radius: 6)

            Text(machine.state.description.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func stateColor(for state: AssistantState) -> Color {
        switch state {
        case .idle: return .gray
        case .listening: return .blue
        case .thinking: return .purple
        case .working: return .orange
        case .success: return .green
        case .error: return .red
        }
    }
}
