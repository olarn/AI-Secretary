import SwiftUI
import AssistantState

/// Original placeholder character: a friendly chibi avatar with teal
/// twin-tails, evoking a generic anime-companion look. This is not licensed
/// character art (e.g. not Hatsune Miku) — swap in a real/licensed asset
/// later behind the same `CharacterView` seam.
private let avatarTeal = Color(red: 0.18, green: 0.75, blue: 0.72)
private let avatarSkin = Color(red: 1.0, green: 0.89, blue: 0.80)

struct MikuAvatarView: View {
    var body: some View {
        ZStack {
            // Twin tails, behind the head.
            Capsule()
                .fill(avatarTeal)
                .frame(width: 16, height: 58)
                .rotationEffect(.degrees(-18))
                .offset(x: -30, y: 10)
            Capsule()
                .fill(avatarTeal)
                .frame(width: 16, height: 58)
                .rotationEffect(.degrees(18))
                .offset(x: 30, y: 10)

            // Head.
            Circle()
                .fill(avatarSkin)
                .frame(width: 58, height: 58)

            // Side hair tufts.
            Circle().fill(avatarTeal).frame(width: 20, height: 22).offset(x: -27, y: -6)
            Circle().fill(avatarTeal).frame(width: 20, height: 22).offset(x: 27, y: -6)

            // Hair top / bangs.
            Capsule()
                .fill(avatarTeal)
                .frame(width: 60, height: 26)
                .offset(y: -22)

            // Eyes.
            HStack(spacing: 16) {
                EyeView()
                EyeView()
            }
            .offset(y: 2)

            // Mouth.
            Capsule()
                .fill(Color.black.opacity(0.55))
                .frame(width: 8, height: 2.5)
                .offset(y: 14)
        }
        .frame(width: 90, height: 90)
    }
}

private struct EyeView: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(avatarTeal.opacity(0.9))
                .frame(width: 10, height: 13)
            Circle()
                .fill(.white)
                .frame(width: 3, height: 3)
                .offset(x: -2, y: -3)
        }
    }
}

/// Small state badge overlaid on the avatar so the assistant lifecycle
/// stays legible regardless of character art.
struct StatusBadge: View {
    let state: AssistantState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 22, height: 22)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    private var color: Color {
        switch state {
        case .idle: return .gray
        case .listening: return .blue
        case .thinking: return .purple
        case .working: return .orange
        case .success: return .green
        case .error: return .red
        }
    }

    private var symbol: String {
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
