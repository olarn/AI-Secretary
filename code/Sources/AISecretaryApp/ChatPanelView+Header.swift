import SwiftUI
import AssistantState
import SecretaryCore

extension ChatPanelView {
    var header: some View {
        HStack(spacing: appearance.settings.panelSpacing) {
            Text(secretary.profile.displayName)
                .font(.system(size: appearance.settings.fontSize, weight: .semibold))
                .layoutPriority(1)
            Text("(\(secretary.modelBadgeText))")
                .font(.system(size: appearance.settings.secondaryFontSize))
                .foregroundStyle(theme.mutedText.color)
                .lineLimit(1)
                .layoutPriority(-1)
            if let tag = characterStatusTag(for: machine.state) {
                Text("- \(tag)")
                    .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                    .foregroundStyle(theme.mutedText.color)
            }
            stopBadge
            subagentBadge
            queueBadge
            loopBadge
            runBadge
            watchBadge
            Spacer()
        }
        .padding(.top, Self.headerTopClearance)
    }

    private var badgeFill: Color {
        appearance.settings.liquidGlass ? theme.chipFill.color : theme.accentFill.color
    }

    @ViewBuilder
    private var subagentBadge: some View {
        if let running = secretary.workingSubagent {
            TimelineView(.periodic(from: .now, by: 5)) { tick in
                HStack(spacing: 3) {
                    Image(systemName: "person.2.badge.gearshape")
                    Text(running.badgeText(now: tick.date))
                        .lineLimit(1)
                }
                .font(.system(size: appearance.settings.secondaryFontSize, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeFill, in: Capsule())
                .help("A sub-agent is working on this. Stop ends the whole turn.")
            }
            .layoutPriority(-1)
        }
    }

    @ViewBuilder
    private var loopBadge: some View {
        if let loop = secretary.runningLoop {
            Button {
                secretary.stopLoop()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                    Text(loop.intervalDescription)
                    Image(systemName: "xmark")
                        .font(.system(size: appearance.settings.secondaryFontSize * 0.7))
                }
                .font(.system(size: appearance.settings.secondaryFontSize, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeFill, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Checking back every \(loop.intervalDescription) — click to stop")
        }
    }

    @ViewBuilder
    private var runBadge: some View {
        if let run = secretary.runningInstructions, run.isRunning {
            Button {
                secretary.stopInstructionRun(because: "you stopped it")
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "list.bullet.rectangle")
                    Text("\(run.stepNumber)/\(run.totalSteps)")
                    Image(systemName: "xmark")
                        .font(.system(size: appearance.settings.secondaryFontSize * 0.7))
                }
                .font(.system(size: appearance.settings.secondaryFontSize, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeFill, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("\(run.progressDescription) — click to stop")
        }
    }

    @ViewBuilder
    private var stopBadge: some View {
        if machine.state.isBusy {
            Button { secretary.stopCurrentTurn(because: "you stopped it") } label: {
                HStack(spacing: 3) {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .font(.system(size: appearance.settings.secondaryFontSize, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.dangerFill.color, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Stop what I'm doing. Whatever it had done is lost.")
        }
    }

    @ViewBuilder
    private var queueBadge: some View {
        let waiting = secretary.queuedMessages.count
        if waiting > 0 || secretary.queuePaused {
            Button { secretary.toggleQueuePause() } label: {
                HStack(spacing: 3) {
                    Image(systemName: secretary.queuePaused ? "pause.fill" : "list.bullet")
                    if waiting > 0 { Text("\(waiting)") }
                }
                .font(.system(size: appearance.settings.secondaryFontSize, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    secretary.queuePaused ? theme.warningFill.color : badgeFill,
                    in: Capsule()
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(
                secretary.queuePaused
                    ? "\(waiting) waiting, held — click to let them go"
                    : "\(waiting) waiting — click to hold"
            )
            if waiting > 0 {
                Button { secretary.clearQueue() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: appearance.settings.secondaryFontSize * 0.8, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Drop what's waiting")
            }
        }
    }

    @ViewBuilder
    private var watchBadge: some View {
        if let first = secretary.activeWatches.first {
            let count = secretary.activeWatches.count
            Button {
                secretary.stopWatching(because: "")
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "eye")
                    if count > 1 { Text("\(count)") }
                    Image(systemName: "xmark")
                        .font(.system(size: appearance.settings.secondaryFontSize * 0.7))
                }
                .font(.system(size: appearance.settings.secondaryFontSize, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeFill, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(
                count == 1
                    ? "Watching \(first.displayName) — click to stop"
                    : "Watching \(secretary.activeWatches.map(\.displayName).joined(separator: ", ")) — click to stop all"
            )
        }
    }

    private static let headerTopClearance: Double = 26
}
