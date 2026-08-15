import AppKit
import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import LLMProvider

/// The conversation panel, rendered as a manga-style speech bubble anchored to
/// the character. Shows the transcript, the input field, whatever decision the
/// Secretary is waiting on, and collapsible Settings/Profile/Projects sections.
struct ChatPanelView: View {
    let machine: AssistantStateMachine
    let secretary: Secretary
    let registry: ProjectRegistry
    let backendStatus: BackendStatus
    let appearance: Appearance
    let profiles: ProfileLibrary
    /// Which character's window this is. Passed to the Profile panel, which
    /// edits her and nobody else.
    let profileID: UUID
    let layout: ChatBubbleLayout
    let onClose: () -> Void
    /// Pins one box into its own floating window. The same door the ```window
    /// marker goes through, so a pane the user pins by hand behaves exactly
    /// like one the assistant asked to pin.
    let onPin: (InfoWindowSpec) -> Void

    /// The colours in force. Every colour in this file comes from a role on
    /// this palette; there are no literals left, because a literal here cannot
    /// be checked — `AISecretaryApp` is not linked into the test bundle.
    var theme: Palette { appearance.colors }

    @State var draft: String = ""
    /// Which configuration section is open, if any.
    ///
    /// One selection rather than three independent flags, because three
    /// independent flags allow all three sections open at once — which is how
    /// the panel came to be taller than the window it lives in, pushing the
    /// transcript off the top and the Save button off the bottom. The state
    /// simply isn't representable now.
    enum Panel: String, Identifiable {
        case settings, profile, projects, skills
        var id: String { rawValue }
        var title: String {
            switch self {
            case .settings: return "Settings"
            case .profile: return "Profile"
            case .projects: return "Projects"
            case .skills: return "Skills"
            }
        }

        /// The row's order lives in `FooterButton`, which knows nothing about
        /// this view's state; this is the one place the two meet.
        init(_ button: FooterButton) {
            switch button {
            case .settings: self = .settings
            case .profile: self = .profile
            case .projects: self = .projects
            case .skills: self = .skills
            }
        }
    }

    @State var openPanel: Panel?
    @State var addProjectNote: String?
    @State var settingsNote: String?
    @State var scrollPin = TranscriptScrollPin()
    @State private var dragOrigin: ChatResizeDrag?
    /// How tall the message being typed actually is, reported by the field
    /// itself. The box is sized from this and capped at five lines.
    @State var draftHeight: Double = 0
    /// How far back through sent messages the box is currently showing.
    /// `nil` means it's showing what you were actually typing.
    @State var recallIndex: Int?
    /// What you were typing before you started looking back, so walking
    /// forward past the newest message returns it rather than losing it.
    @State var stashedDraft = ""
    @FocusState var messageBoxFocused: Bool
    /// Watches for the arrow keys before the text field sees them.
    @State var arrowKeyMonitor: Any?
    /// Watches for the reader scrolling the transcript themselves.
    @State var scrollMonitor: Any?
    /// How each message was last broken into boxes. A reference type on
    /// purpose: it is a memo of a pure function, not state the view renders,
    /// and writing to it must not invalidate anything.
    @State var partsCache = MessagePartsCache()
    /// Whether the pointer is over the transcript. A local monitor sees every
    /// scroll in the app — the history window, the settings panel, a pinned
    /// message — and only the ones aimed at the transcript say anything about
    /// where the reader wants the transcript to be.
    @State var pointerOverTranscript = false
    /// Which option is highlighted in the choice list, when one is showing.
    @State var choiceIndex = 0
    /// Which box the pointer is over and which was last copied.
    ///
    /// An object rather than two `@State` values, and this is a performance
    /// decision with a rule attached: **nothing in `ChatPanelView.body` may
    /// read `hover.pointingAt` or `hover.copied`.** Reading an `@Observable`
    /// property is what subscribes a view to it, so a single read here puts the
    /// whole transcript back on the hot path — and the symptom is invisible
    /// until someone scrolls a long thread.
    ///
    /// When they were `@State`, every box passing under the pointer during a
    /// scroll rebuilt the entire panel: 19 rebuilds over a 120-tick scroll,
    /// each one re-measuring all 60 messages through TextKit at ~0.2ms each.
    /// That is the stutter. The reads now happen only inside `WhenPointingAt`,
    /// which is a leaf, so a hover change repaints two buttons and nothing else.
    @State var hover = BoxHover()
    /// Whether a file is being dragged over the composer, so there is an
    /// outline to let go inside rather than a guess.
    @State var droppingFile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if backendStatus.needsOnboarding { onboardingCard }
            transcript
            choiceList
            pendingDecisionView
            inputRow
            openPanelSection
            footer
        }
        .padding(18)
        // The default for anything that doesn't name a colour, so a `Text` added
        // later inherits the palette instead of the system label colour — which
        // is decided by the system's light/dark setting, not by ours, and would
        // be black text on a dark panel the moment the theme is overridden.
        .foregroundStyle(theme.primaryText.color)
        .tint(theme.accent.color)
        .environment(\.palette, theme)
        .onAppear {
            startWatchingArrowKeys()
            startWatchingScroll()
        }
        .onDisappear {
            stopWatchingArrowKeys()
            stopWatchingScroll()
        }
        // Not `onAppear`: this view is built once and then shown and hidden by
        // the window's alpha, so appearing happens exactly one time.
        //
        // Only into an empty box. Taking focus selects whatever is already
        // there, so re-opening on a half-written message armed the next
        // keystroke to wipe it — the box is where their words live, and this
        // was meant to save a click, not cost a sentence.
        .onChange(of: layout.focusRequests) {
            if draft.isEmpty { messageBoxFocused = true }
        }
        .frame(width: appearance.settings.chatWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            SpeechBubbleShape(isMirrored: layout.isMirrored, isFlippedVertically: layout.isFlippedVertically)
                .fill(theme.ground.color)
        )
        .overlay(
            SpeechBubbleShape(isMirrored: layout.isMirrored, isFlippedVertically: layout.isFlippedVertically)
                .stroke(theme.panelBorder.color, lineWidth: theme.panelBorderWidth)
        )
        // The button row stays on the tail's side of the top edge; the grip goes
        // to the corner the bubble actually grows out of, which is not always a
        // top corner. Both follow the bubble as it mirrors and flips, and they
        // can never land in the same place.
        //
        // Attached inside the body rather than to the outer frame: the outer
        // frame includes the strip reserved for the tail, and anything aligned
        // to the bottom of it would sit in the tail, outside the bubble.
        .overlay(alignment: buttonsOnLeading ? .topLeading : .topTrailing) { windowButtons }
        .overlay(alignment: gripAlignment) { resizeGrip }
        .padding(layout.isFlippedVertically ? .top : .bottom, SpeechBubbleShape.defaultTailLength)
        .frame(width: appearance.settings.chatWidth, height: appearance.settings.chatHeight)
    }

    /// Widen, restore, close — reversed when the row moves to the other corner,
    /// so close stays on the outside and the two width buttons stay next to the
    /// middle of the bubble. The width buttons are drawn smaller than the close
    /// button (closing is the one people reach for) and are disabled rather than
    /// hidden when they'd do nothing, so the row never changes shape and a greyed
    /// button reads as "already there".
    private var windowButtons: some View {
        HStack(spacing: 8) {
            if buttonsOnLeading {
                closeButton
                restoreButton
                widenButton
            } else {
                widenButton
                restoreButton
                closeButton
            }
        }
        .foregroundStyle(theme.mutedText.color)
        .buttonStyle(.plain)
        .padding(.top, 10)
        .padding(buttonsOnLeading ? .leading : .trailing, 10)
    }

    /// Which top corner the button row gets: the tail's side, so it follows the
    /// bubble when it mirrors. The grip's corner is `gripCorner`, which is kept
    /// clear of this one.
    ///
    /// This only moves them. What the buttons *do* is decided elsewhere and
    /// doesn't depend on where they are: widening still steps, restoring still
    /// goes straight to the default, and the drag still follows the direction
    /// the bubble grows rather than the grip's own corner.
    private var buttonsOnLeading: Bool { !layout.isMirrored }

    /// Which corner the grip gets, and which way its glyph points there.
    ///
    /// Horizontally it stays opposite the button row, on the side the bubble
    /// grows into. Vertically it follows the edge that actually moves: the top
    /// normally, the bottom once the bubble has been flipped below the character,
    /// where the tail pins the top edge instead. Left at the top through a flip,
    /// the grip asked you to drag downward — into the character — while the empty
    /// half of the screen it was growing into lay past the other end of the box.
    var gripCorner: GripCorner {
        GripCorner.forBubble(isMirrored: layout.isMirrored, isFlippedVertically: layout.isFlippedVertically)
    }

    private var gripAlignment: Alignment {
        switch (gripCorner.isBottom, gripCorner.isLeading) {
        case (false, false): .topTrailing
        case (false, true): .topLeading
        case (true, false): .bottomTrailing
        case (true, true): .bottomLeading
        }
    }

    private var widenButton: some View {
        Button(action: appearance.widenChat) {
            Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
        }
        .font(.system(size: Self.widthButtonSize))
        .disabled(!appearance.settings.canWiden)
        .help("Wider — one step at a time, up to three times")
    }

    private var restoreButton: some View {
        Button(action: appearance.restoreChatWidth) {
            Image(systemName: "arrow.right.and.line.vertical.and.arrow.left")
        }
        .font(.system(size: Self.widthButtonSize))
        .disabled(!appearance.settings.canRestoreWidth)
        .help("Back to the default width")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
        }
        .font(.system(size: Self.closeButtonSize))
        .help("Close")
    }

    /// The filled circle behind the ✕ makes it read larger than its point size,
    /// so it's set 10% down from the 18pt the other controls were measured
    /// against.
    private static let closeButtonSize: Double = 18 * 0.9
    /// 30% smaller again than the close button's original 18pt.
    private static let widthButtonSize: Double = 18 * 0.7

    /// Free resize in both axes at once, for when neither the widen button nor
    /// the height steppers give the size the user wants.
    ///
    /// Measured against the pointer's position on screen rather than the
    /// gesture's own translation: the bubble is re-anchored to the character on
    /// every size change, so it moves under the pointer mid-drag and a
    /// translation reported in the window's own coordinates would drift.
    private var resizeGrip: some View {
        // The glyph flips with the corner, so the arrows always point out of it:
        // ↖↘ at top-leading and bottom-trailing, ↗↙ at the other two.
        Image(systemName: gripCorner.glyphName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(theme.mutedText.color)
            // Enough to sit clear of the bubble's rounded corner rather than
            // tucked into it. This is also the grip's hit area, and at a bottom
            // corner it is what the footer row has to stay above — so it is as
            // small as a corner target can be and no smaller, rather than sized
            // for looks alone.
            .padding(10)
            .contentShape(Rectangle())
            .help("Drag to resize")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in resize(to: NSEvent.mouseLocation) }
                    .onEnded { _ in dragOrigin = nil }
            )
    }

    /// Drag the grip the way you want the bubble to extend, on both axes at once.
    ///
    /// The rule — which edges grow, why the directions are captured once at the
    /// start of the drag, and the oscillation that reading them fresh caused —
    /// is `ChatResizeDrag` in SecretaryCore, where it has tests. This only
    /// feeds it the current layout and applies the answer.
    ///
    /// Note the drag is keyed to the layout, not to the corner the grip happens
    /// to be in — only the layout says which edges are free to move. The two
    /// agree on all four axes now that `GripCorner` puts the grip on the
    /// growing corner, so the drag reads both ways at once: "the way you want
    /// the box to extend" and the usual corner-handle "away from the box".
    private func resize(to pointer: CGPoint) {
        let settings = appearance.settings
        let origin = dragOrigin ?? ChatResizeDrag(
            pointer: pointer,
            width: settings.chatWidth,
            height: settings.chatHeight,
            isMirrored: layout.isMirrored,
            isFlippedVertically: layout.isFlippedVertically
        )
        if dragOrigin == nil { dragOrigin = origin }

        let size = origin.size(at: pointer)
        appearance.resizeChat(width: size.width, height: size.height)
    }

    // MARK: - Sections

    /// Shown only once detection has finished and found nothing. The two steps
    /// are both required: a user can have the binary installed but not signed
    /// in, and that failure would otherwise only surface on the first turn.
    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            Label("Claude Code isn't set up", systemImage: "exclamationmark.triangle")
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
            Text("I work by driving your own copy of Claude Code, so it stays on your account. Two steps:")
                .font(.system(size: appearance.settings.footnoteFontSize))
            Text("1. Install it — see claude.com/claude-code\n2. Run `claude` in Terminal once and sign in")
                .font(.system(size: appearance.settings.footnoteFontSize, design: .monospaced))
                .textSelection(.enabled)
            Text("Then reopen this panel. If it's installed somewhere unusual, I also check your login shell's PATH.")
                .font(.system(size: appearance.settings.footnoteFontSize))
                .foregroundStyle(theme.mutedText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(appearance.settings.panelPadding)
        .background(theme.warningFill.color, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var pendingDecisionView: some View {
        switch secretary.awaitingDecision {
        case .approval(let request, _):
            // Anything that isn't read-only leaves a mark somewhere — currently
            // that means sending a file off this Mac. Give it a louder colour so
            // it never looks like the routine local approval.
            let leavesTheMachine = request.actionClass != .readOnly
            // "Send to Claude?" is right for a file leaving the Mac and wrong
            // for a click inside the user's own browser — nothing is being
            // sent, something is being done, as them.
            let inBrowser = request.actionClass == .browserAction
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
                Label(
                    inBrowser
                        ? "Act in your browser?"
                        : (leavesTheMachine ? "Send to Claude?" : "Approval required"),
                    systemImage: inBrowser
                        ? "globe"
                        : (leavesTheMachine ? "paperplane.circle" : "lock.shield")
                )
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                Text(request.commandSummary)
                    .font(.system(size: appearance.settings.footnoteFontSize, design: .monospaced))
                Text("in \(request.project.name) · \(request.actionClass.humanDescription)")
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .foregroundStyle(theme.mutedText.color)
                HStack(spacing: appearance.settings.panelSpacing * 1.3) {
                    Button("Approve") { secretary.resolvePendingApproval(granted: true) }
                        .buttonStyle(.borderedProminent)
                    Button("Deny") { secretary.resolvePendingApproval(granted: false) }
                        .buttonStyle(.bordered)
                }
                .font(.system(size: appearance.settings.footnoteFontSize))
            }
            .padding(appearance.settings.panelPadding)
            .background(
                (leavesTheMachine ? theme.dangerFill : theme.warningFill).color,
                in: RoundedRectangle(cornerRadius: 8)
            )

        case .interruption(let text, _):
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
                Label("I'm still on the last one", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                Text(text)
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .foregroundStyle(theme.mutedText.color)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: appearance.settings.panelSpacing * 1.3) {
                    Button("Wait its turn") { secretary.resolveInterruption(queue: true) }
                        .buttonStyle(.borderedProminent)
                    // Says what it costs. The running turn is a CLI invocation
                    // that can't be paused or resumed, so replacing it throws
                    // away whatever it had done.
                    Button("Replace — drop what's running") {
                        secretary.resolveInterruption(queue: false)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.system(size: appearance.settings.footnoteFontSize))
            }
            .padding(appearance.settings.panelPadding)
            .background(theme.accentFill.color, in: RoundedRectangle(cornerRadius: 8))

        case .projectChoice(let candidates, _):
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
                Label("Choose a project", systemImage: "folder")
                    .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                ForEach(candidates) { candidate in
                    Button(candidate.name) { secretary.choose(project: candidate) }
                        .buttonStyle(.bordered)
                        .font(.system(size: appearance.settings.footnoteFontSize))
                }
                Button("Cancel") { secretary.cancelPendingDecision() }
                    .buttonStyle(.plain)
                    .font(.system(size: appearance.settings.footnoteFontSize))
            }
            .padding(appearance.settings.panelPadding)
            .background(theme.accentFill.color, in: RoundedRectangle(cornerRadius: 8))

        case .website(let request):
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
                Label("Work in this site as you?", systemImage: "globe")
                    .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                Text(request.url.absoluteString)
                    .font(.system(size: appearance.settings.footnoteFontSize, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                // Says what the grant covers and how long it lasts. "This site"
                // is the unit that was approved, not this one page, and the
                // person should read that here rather than discover it later.
                Text(
                    request.connectsBrowser
                        ? "Connects Chrome, then acts as you on \(request.host) for this conversation"
                        : "Acts as you on \(request.host) for this conversation"
                )
                .font(.system(size: appearance.settings.footnoteFontSize))
                .foregroundStyle(theme.mutedText.color)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: appearance.settings.panelSpacing * 1.3) {
                    Button("Go ahead") { secretary.resolveWebTask(granted: true) }
                        .buttonStyle(.borderedProminent)
                    Button("Not this one") { secretary.resolveWebTask(granted: false) }
                        .buttonStyle(.bordered)
                }
                .font(.system(size: appearance.settings.footnoteFontSize))
            }
            .padding(appearance.settings.panelPadding)
            .background(theme.warningFill.color, in: RoundedRectangle(cornerRadius: 8))

        case .instructionPlan(let plan, let risks, let changed):
            InstructionPlanCard(
                plan: plan,
                risks: risks,
                changedSinceLastRun: changed,
                fontSize: appearance.settings.footnoteFontSize,
                hintSize: appearance.settings.hintFontSize,
                spacing: appearance.settings.panelSpacing,
                padding: appearance.settings.panelPadding,
                start: { secretary.startPlannedInstructions() },
                cancel: { secretary.cancelPendingDecision() }
            )
            // A new plan is a new decision: the acknowledgement inside must not
            // carry over from the last one the user waved through.
            .id(plan.fingerprint)

        case nil:
            EmptyView()
        }
    }

}
