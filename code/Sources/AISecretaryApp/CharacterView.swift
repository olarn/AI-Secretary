import SwiftUI
import AppKit
import AssistantState
import SecretaryCore

struct CharacterView: View {
    let machine: AssistantStateMachine
    let secretary: Secretary
    let profiles: ProfileLibrary
    let profileID: UUID
    let appearance: Appearance
    let onTap: () -> Void

    var body: some View {
        content
            .fixedSize()
            .scaleEffect(appearance.settings.characterScale.factor)
    }

    private var content: some View {
        VStack(spacing: 6) {
            ZStack {
                halo

                characterArt
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: secretary.toggleActivityVisibility) {
                    StatusBadge(state: machine.state)
                        .opacity(secretary.showsActivity ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .help(secretary.showsActivity ? "Hide what I'm doing" : "Show what I'm doing")
                .offset(x: 2, y: 2)
            }
            .shadow(radius: 6)

            Text(characterStatusLabel(name: secretary.profile.displayName, state: machine.state))
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var halo: some View {
        let pulse = statusPulse(for: machine.state)
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pulse.isAnimated)) { context in
            let progress = pulseProgress(pulse, at: context.date.timeIntervalSinceReferenceDate)
            Circle()
                .fill((pulse.isAnimated ? Color.gray : stateColor(for: machine.state)).opacity(0.25))
                .overlay(Circle().fill(stateColor(for: machine.state).opacity(0.25 * progress)))
                .frame(width: 104, height: 104)
        }
        .frame(width: 104, height: 104)
    }

    @ViewBuilder
    private var characterArt: some View {
        if let nsImage = artworkImage {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 104)
        } else {
            MikuAvatarView()
        }
    }

    private var artworkImage: NSImage? {
        _ = profiles.artworkRevision
        if let url = profiles.artworkFileURL(for: profileID), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(contentsOf: CharacterAsset.url)
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

enum CharacterAsset {
    static var url: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
            .appendingPathComponent("character.png")
    }
}
