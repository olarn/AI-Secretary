import SwiftUI
import AssistantState

private let avatarTeal = Color(red: 0.16, green: 0.74, blue: 0.72)
private let avatarTealLight = Color(red: 0.55, green: 0.90, blue: 0.88)
private let avatarSkin = Color(red: 1.0, green: 0.90, blue: 0.82)

struct MikuAvatarView: View {
    var body: some View {
        ZStack {
            twinTail.rotationEffect(.degrees(-16)).offset(x: -32, y: 12)
            twinTail.rotationEffect(.degrees(16)).offset(x: 32, y: 12)
                .scaleEffect(x: -1, y: 1)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.9))
                .frame(width: 34, height: 16)
                .offset(y: 34)
            Triangle()
                .fill(avatarTeal)
                .frame(width: 10, height: 12)
                .offset(y: 32)

            Circle()
                .fill(avatarSkin)
                .frame(width: 58, height: 58)

            Circle().fill(avatarTeal).frame(width: 22, height: 24).offset(x: -27, y: -4)
            Circle().fill(avatarTeal).frame(width: 22, height: 24).offset(x: 27, y: -4)

            BangsShape()
                .fill(avatarTeal)
                .frame(width: 60, height: 30)
                .offset(y: -20)

            HStack(spacing: 15) {
                EyeView()
                EyeView()
            }
            .offset(y: 3)

            SmileShape()
                .fill(Color(red: 0.55, green: 0.2, blue: 0.2))
                .frame(width: 12, height: 7)
                .offset(y: 15)
        }
        .frame(width: 90, height: 90)
    }

    private var twinTail: some View {
        ZStack {
            Capsule().fill(avatarTeal).frame(width: 17, height: 60)
            Capsule().fill(avatarTealLight).frame(width: 6, height: 42)
                .offset(x: -2, y: -4)
        }
    }
}

private struct EyeView: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(avatarTeal.opacity(0.92))
                .frame(width: 11, height: 14)
            Ellipse()
                .fill(Color.black.opacity(0.65))
                .frame(width: 6, height: 8)
                .offset(y: 2)
            Circle()
                .fill(.white)
                .frame(width: 3, height: 3)
                .offset(x: -2, y: -3)
            Circle()
                .fill(.white.opacity(0.8))
                .frame(width: 1.5, height: 1.5)
                .offset(x: 1.5, y: 1)
        }
    }
}

private struct BangsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX - 4, y: rect.minY + 4),
            control: CGPoint(x: rect.minX + 2, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + 4, y: rect.minY + 4),
            control: CGPoint(x: rect.midX, y: rect.minY + 10)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - 2, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct StatusBadge: View {
    let state: AssistantState

    var body: some View {
        let pulse = statusPulse(for: state)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pulse.isAnimated)) { context in
            let progress = pulseProgress(pulse, at: context.date.timeIntervalSinceReferenceDate)
            Circle()
                .fill(pulse.isAnimated ? Color.gray : color)
                .overlay(Circle().fill(color.opacity(progress)))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .scaleEffect(pulseScale(pulse, at: context.date.timeIntervalSinceReferenceDate))
        }
        .frame(width: 22, height: 22)
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
