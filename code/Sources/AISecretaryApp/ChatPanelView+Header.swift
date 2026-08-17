import SwiftUI
import AssistantState
import SecretaryCore

/// The header row: who is speaking, what state she is in, and the badges for
/// everything standing that can speak on its own — each with its own off
/// switch, because a turn arriving with nobody typing must have a visible
/// cause.
extension ChatPanelView {
    /// What the assistant is doing right now.
    ///
    /// Note this is activity, not reasoning: Claude Code returns thinking
    /// blocks with no text (the raw chain of thought isn't exposed on this
    /// model family), so there is nothing to render for the thought itself.
    /// Which tool it reached for, and with what, is the part that exists.
    var header: some View {
        HStack(spacing: appearance.settings.panelSpacing) {
            Text(secretary.profile.displayName)
                .font(.system(size: appearance.settings.fontSize, weight: .semibold))
                .layoutPriority(1)
            // Which model is answering, beside the name that answers. Two
            // characters on one desktop can be on different models and efforts,
            // and until now the only way to tell was to open Settings for each.
            //
            // Lowest layout priority in the row: the badge is the one thing
            // here that may be truncated, because everything else is either the
            // name or a control with an off switch on it.
            Text("(\(secretary.modelBadgeText))")
                .font(.system(size: appearance.settings.secondaryFontSize))
                .foregroundStyle(theme.mutedText.color)
                .lineLimit(1)
                .layoutPriority(-1)
            // Two Texts rather than the whole label from `characterStatusLabel`,
            // so the name keeps its weight and the state stays secondary — but
            // the same rule decides whether there is a state to show at all.
            if let tag = characterStatusTag(for: machine.state) {
                Text("- \(tag)")
                    .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                    .foregroundStyle(theme.mutedText.color)
            }
            stopBadge
            queueBadge
            loopBadge
            runBadge
            watchBadge
            Spacer()
        }
        // A top corner is taken by the widen/restore/close row, and can be taken
        // by the resize grip as well, so the title drops below them rather than
        // being inset past them. Inset was the first attempt and it moved the name
        // around as the bubble mirrored; the title now stays flush left at every
        // size, on either side, and whichever corner the grip is in.
        .padding(.top, Self.headerTopClearance)
    }

    /// Shows that the Secretary is on a timer, and stops it in one click.
    ///
    /// Something that speaks without being spoken to has to be visible while it
    /// is armed, not only in the message that announced it — that message
    /// scrolls away, and then an answer arriving on its own has no explanation
    /// anywhere on screen.
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
                .background(theme.accentFill.color, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Checking back every \(loop.intervalDescription) — click to stop")
        }
    }

    /// Shows that a file's steps are being worked through, and stops them in
    /// one click. Same reasoning as `loopBadge`: turns that keep arriving
    /// without anyone typing must have a visible cause and a visible off
    /// switch, not just the message that announced them three screens ago.
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
                .background(theme.accentFill.color, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("\(run.progressDescription) — click to stop")
        }
    }

    /// Shows that a path is being watched, and stops it in one click. Third of
    /// the three standing things that speak on their own; all three sit in the
    /// header for the same reason.
    /// Stops what is running. Only there while something is.
    ///
    /// The running turn is one invocation of the CLI, so this is the only
    /// interruption that exists for it — there is nothing to pause and resume.
    /// Pausing belongs to the queue, on the badge beside this.
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

    /// What is waiting, and whether it is being held.
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
                    (secretary.queuePaused ? theme.warningFill : theme.accentFill).color,
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
            // Holding something for ever is not the same as changing your mind
            // about it. Without this, a message queued by mistake could only be
            // paused, never dropped.
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
                    // The number only appears when there is more than one:
                    // a "1" beside the eye reads as a badge count of unread
                    // things rather than as how many are being watched.
                    if count > 1 { Text("\(count)") }
                    Image(systemName: "xmark")
                        .font(.system(size: appearance.settings.secondaryFontSize * 0.7))
                }
                .font(.system(size: appearance.settings.secondaryFontSize, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.accentFill.color, in: Capsule())
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

    /// Enough to clear the control row above, whose lowest point is ~29pt below
    /// the bubble's top edge (10pt of padding plus an 18pt close button). The
    /// title's own top already sits 18pt in, so this is the remainder — plus
    /// breathing room, because merely not overlapping still read as crowded.
    private static let headerTopClearance: Double = 26
}
