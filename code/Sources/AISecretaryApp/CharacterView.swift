import SwiftUI
import AppKit
import AssistantState

/// Desktop companion character. Displays a locally-provided character image
/// if the user has placed one (see `CharacterAsset`), otherwise falls back
/// to the built-in placeholder avatar; a small state badge and tap-to-open
/// remain the same either way.
struct CharacterView: View {
    let machine: AssistantStateMachine
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(stateColor(for: machine.state).opacity(0.25))
                    .frame(width: 104, height: 104)

                characterArt

                StatusBadge(state: machine.state)
                    .offset(x: 2, y: 2)
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

    @ViewBuilder
    private var characterArt: some View {
        if let nsImage = NSImage(contentsOf: CharacterAsset.url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 104)
        } else {
            MikuAvatarView()
        }
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

/// A user-supplied character image, loaded from outside the git repo so
/// licensed/copyrighted art never gets committed or distributed with the
/// project. Drop a PNG at this path to override the built-in placeholder;
/// remove it to fall back automatically.
enum CharacterAsset {
    static var url: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
            .appendingPathComponent("character.png")
    }
}
