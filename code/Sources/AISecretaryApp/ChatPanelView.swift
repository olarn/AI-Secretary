import AppKit
import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import Credentials
import LLMProvider

/// The conversation panel, rendered as a manga-style speech bubble anchored to
/// the character. Shows the transcript, the input field, whatever decision the
/// Secretary is waiting on, and collapsible Settings/Profile/Projects sections.
struct ChatPanelView: View {
    let machine: AssistantStateMachine
    let secretary: Secretary
    let registry: ProjectRegistry
    let credentials: any CredentialStore
    let backendStatus: BackendStatus
    let appearance: Appearance
    let profiles: ProfileLibrary
    let layout: ChatBubbleLayout
    let onClose: () -> Void
    /// Pins one box into its own floating window. The same door the ```window
    /// marker goes through, so a pane the user pins by hand behaves exactly
    /// like one the assistant asked to pin.
    let onPin: (InfoWindowSpec) -> Void

    @State private var draft: String = ""
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

    @State private var openPanel: Panel?
    @State private var addProjectNote: String?
    @State private var apiKeyDraft: String = ""
    @State private var settingsNote: String?
    @State private var scrollPin = TranscriptScrollPin()
    @State private var dragOrigin: DragOrigin?
    /// How tall the message being typed actually is, reported by the field
    /// itself. The box is sized from this and capped at five lines.
    @State private var draftHeight: Double = 0
    /// How far back through sent messages the box is currently showing.
    /// `nil` means it's showing what you were actually typing.
    @State private var recallIndex: Int?
    /// What you were typing before you started looking back, so walking
    /// forward past the newest message returns it rather than losing it.
    @State private var stashedDraft = ""
    @FocusState private var messageBoxFocused: Bool
    /// Watches for the arrow keys before the text field sees them.
    @State private var arrowKeyMonitor: Any?
    /// Which option is highlighted in the choice list, when one is showing.
    @State private var choiceIndex = 0
    /// Which box was last copied, so its button can show a tick.
    @State private var copiedBox: BoxID?
    /// Which box the pointer is over, so only that one shows its copy button.
    @State private var hoveredBox: BoxID?

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
        .onAppear { startWatchingArrowKeys() }
        .onDisappear { stopWatchingArrowKeys() }
        .frame(width: appearance.settings.chatWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            SpeechBubbleShape(isMirrored: layout.isMirrored, isFlippedVertically: layout.isFlippedVertically)
                .fill(.regularMaterial)
        )
        .overlay(
            SpeechBubbleShape(isMirrored: layout.isMirrored, isFlippedVertically: layout.isFlippedVertically)
                .stroke(Color.primary.opacity(0.85), lineWidth: 2)
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
        .foregroundStyle(.secondary)
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
    private var gripCorner: GripCorner {
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
    /// Asked for: the message box grows to five lines and then scrolls. Past
    /// five it starts eating the conversation it's replying to.
    static let inputLineLimit = 5

    /// The box grows with the message and stops at five lines, after which it
    /// scrolls — by wheel or trackpad as well as by caret.
    ///
    /// The field is left to grow to its full height and a `ScrollView` is what's
    /// capped, rather than capping the field with `lineLimit`. Both look the same
    /// until you reach for the wheel: a line-limited field scrolls only to follow
    /// the caret, and a wheel over it does nothing at all.
    private var messageBox: some View {
        ScrollView(.vertical) {
            // The persona's own name, not "the Secretary": the app can be
            // several people and the box should ask for whoever is listening.
            TextField("", text: $draft, prompt: Text("Ask \(secretary.profile.displayName)…"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: appearance.settings.fontSize))
                // Return sends. `onSubmit` doesn't fire for a vertical field in
                // this panel — Return quietly drops first responder instead —
                // which would leave no way to send from the keyboard.
                // Shift/Option-Return is left alone so it still breaks the line.
                .onKeyPress(.return, phases: .down) { press in
                    let newlineKeys: EventModifiers = [.shift, .option]
                    guard press.modifiers.isDisjoint(with: newlineKeys) else {
                        // Inserted here rather than passed on. Handing Shift+Return
                        // back to the field left it doing nothing at all — the
                        // modifier is swallowed and the line never breaks — which
                        // is why only Option+Return worked.
                        draft.append("\n")
                        return .handled
                    }
                    send()
                    return .handled
                }
                .focused($messageBoxFocused)
                // The lane the ↵ sits in. Taken out of the field's own width so
                // the text wraps before it rather than running underneath —
                // an overlay alone would have let a long line slide behind it.
                .padding(.trailing, sendGlyphLane)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: MessageBoxHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .onPreferenceChange(MessageBoxHeightKey.self) { draftHeight = $0 }
        .frame(height: messageBoxHeight)
        // Nothing to scroll until it has outgrown the box; without this the
        // content drifts under a trackpad's rubber-banding while still short.
        .scrollDisabled(draftHeight <= maxMessageBoxHeight)
        // Keeps the newest line in view as the message grows, which is where the
        // caret is while typing.
        .defaultScrollAnchor(.bottom)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) { sendGlyph }
    }

    /// One line of the message font, measured rather than guessed — a fraction
    /// of the point size is wrong by a whole line at the larger text sizes.
    private var messageLineHeight: Double {
        Double(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: appearance.settings.fontSize)))
    }

    private var maxMessageBoxHeight: Double { messageLineHeight * Double(Self.inputLineLimit) }

    private var messageBoxHeight: Double {
        min(max(draftHeight, messageLineHeight), maxMessageBoxHeight)
    }

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
            .foregroundStyle(.secondary)
            // Enough to sit clear of the bubble's rounded corner rather than
            // tucked into it, and to match the inset of the button row opposite.
            .padding(14)
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
    /// The edges on the tail's side stay pinned to the character — the tail must
    /// not slide off it just because the window got bigger — so the bubble only
    /// ever grows into the two opposite edges, and the drag follows those. Which
    /// way that is depends on where the bubble has been placed: it grows right
    /// and up in the usual position, left when mirrored, down when it has been
    /// flipped below the character.
    ///
    /// Note this is keyed to the layout, not to the corner the grip happens to
    /// be in — only the layout says which edges are free to move. The two agree
    /// on all four axes now that `GripCorner` puts the grip on the growing
    /// corner, so the drag reads both ways at once: "the way you want the box to
    /// extend" and the usual corner-handle "away from the box". They did not
    /// always. With the grip pinned to the top through a vertical flip, growing
    /// downward meant dragging down past a grip that stayed put, toward the
    /// character, with the space being filled behind you.
    private func resize(to pointer: CGPoint) {
        let settings = appearance.settings
        let origin = dragOrigin ?? DragOrigin(
            pointer: pointer,
            width: settings.chatWidth,
            height: settings.chatHeight,
            growsRight: layout.isMirrored ? -1 : 1,
            // Screen coordinates point up, so this is already "up is taller"
            // unless the bubble sits below the character and grows downward.
            growsUp: layout.isFlippedVertically ? -1 : 1
        )
        if dragOrigin == nil { dragOrigin = origin }

        appearance.resizeChat(
            width: origin.width + (pointer.x - origin.pointer.x) * origin.growsRight,
            height: origin.height + (pointer.y - origin.pointer.y) * origin.growsUp
        )
    }

    /// Where the drag started, so every step is measured from one fixed point
    /// rather than accumulated.
    struct DragOrigin {
        let pointer: CGPoint
        let width: Double
        let height: Double
        /// Which way the bubble grows, fixed for the whole drag. Read fresh on
        /// every event instead, a layout that flips mid-drag inverts the
        /// gesture: keep dragging the same way and the box shrinks, which
        /// un-flips it, which grows it again. Measured at the top of the
        /// screen, the height oscillated 909 → 801 → 933 → 777 in four events,
        /// the swing widening each time.
        let growsRight: Double
        let growsUp: Double
    }

    // MARK: - Sections

    private var emptyTranscriptHint: String {
        if backendStatus.needsOnboarding {
            return "Install Claude Code and sign in, and I'll be able to work for you."
        }
        if let installation = backendStatus.installation {
            let version = installation.version.map { " (\($0))" } ?? ""
            return """
            Ready — I'll work through your own Claude Code\(version).             Add a project, then just tell me what you need in your own words.
            """
        }
        return "Checking for Claude Code…"
    }

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
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(appearance.settings.panelPadding)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Clicking the name opens a real picker. The same entry point the slash
    /// commands use, so a change here is announced in the transcript too — the
    /// conversation is where the change takes effect, so that's where it should
    /// be visible.
    private var modelPicker: some View {
        Menu {
            Button {
                secretary.chooseModel(nil)
            } label: {
                Label(
                    "Your Claude Code default",
                    systemImage: secretary.isModelInherited ? "checkmark" : ""
                )
            }
            Divider()
            ForEach(ChatModel.known, id: \.id) { candidate in
                Button {
                    secretary.chooseModel(candidate)
                } label: {
                    Label(
                        candidate.displayName,
                        systemImage: secretary.chosenModel == candidate ? "checkmark" : ""
                    )
                }
            }
        } label: {
            settingLabel(
                "Model",
                value: secretary.effectiveModelName,
                inherited: secretary.isModelInherited
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var effortPicker: some View {
        Menu {
            Button {
                secretary.chooseEffort(nil)
            } label: {
                Label(
                    "Your Claude Code default",
                    systemImage: secretary.isEffortInherited ? "checkmark" : ""
                )
            }
            Divider()
            ForEach(Effort.allCases, id: \.rawValue) { candidate in
                Button {
                    secretary.chooseEffort(candidate)
                } label: {
                    Label(
                        candidate.rawValue,
                        systemImage: secretary.chosenEffort == candidate ? "checkmark" : ""
                    )
                }
            }
        } label: {
            settingLabel(
                "Effort",
                value: secretary.effectiveEffortName,
                inherited: secretary.isEffortInherited
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// The same menu shape as Model and Effort rather than a toggle switch, so
    /// the settings panel reads as one list of choices — and so this one is a
    /// deliberate pick from a menu, not a switch brushed by accident.
    private var browserPicker: some View {
        HStack(spacing: 3) {
            // Outside the menu on purpose. A menu label built from several
            // views renders as the title and the chevron alone here — which is
            // why Model and Effort show no value — and the one thing this row
            // has to say is whether the browser is connected.
            Text("Browser:").foregroundStyle(.secondary)
            browserMenu
        }
        .font(.system(size: appearance.settings.footnoteFontSize))
    }

    private var browserMenu: some View {
        Menu {
            Button {
                secretary.setBrowserEnabled(false)
            } label: {
                Label("Off", systemImage: secretary.browserEnabled ? "" : "checkmark")
            }
            Button {
                secretary.setBrowserEnabled(true)
            } label: {
                Label("Read my browser", systemImage: secretary.browserEnabled ? "checkmark" : "")
            }
        } label: {
            Text(secretary.browserEnabled ? "Connected" : "Off")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Shows the real value either way; the dot marks one the app didn't pick,
    /// which can change if the user reconfigures Claude Code.
    private func settingLabel(_ title: String, value: String, inherited: Bool) -> some View {
        HStack(spacing: appearance.settings.panelSpacing * 0.5) {
            Text("\(title):").foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary)
            if inherited {
                Image(systemName: "circle.dashed")
                    .font(.system(size: appearance.settings.hintFontSize * 0.8))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: appearance.settings.footnoteFontSize))
    }

    /// What the assistant is doing right now.
    ///
    /// Note this is activity, not reasoning: Claude Code returns thinking
    /// blocks with no text (the raw chain of thought isn't exposed on this
    /// model family), so there is nothing to render for the thought itself.
    /// Which tool it reached for, and with what, is the part that exists.
    private var header: some View {
        HStack(spacing: appearance.settings.panelSpacing) {
            Text(secretary.profile.displayName)
                .font(.system(size: appearance.settings.fontSize, weight: .semibold))
            Text(machine.state.description.uppercased())
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
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
        if let loop = secretary.activeLoop {
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
                .background(Color.accentColor.opacity(0.22), in: Capsule())
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
        if let run = secretary.activeInstructionRun, run.isRunning {
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
                .background(Color.accentColor.opacity(0.22), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("\(run.progressDescription) — click to stop")
        }
    }

    /// Shows that a path is being watched, and stops it in one click. Third of
    /// the three standing things that speak on their own; all three sit in the
    /// header for the same reason.
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
                .background(Color.accentColor.opacity(0.22), in: Capsule())
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

    private var transcript: some View {
        // The outer geometry gives the viewport height; the one behind the
        // content reports where the content's bottom currently sits in the same
        // space. The difference is how far from the bottom the reader is.
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    // Wider than the gap between boxes of one turn, so the eye
                    // groups a split answer together before it groups the
                    // conversation.
                    VStack(alignment: .leading, spacing: 16) {
                        if secretary.transcript.isEmpty {
                            Text(emptyTranscriptHint)
                                .font(.system(size: appearance.settings.fontSize))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(secretary.transcript) { entry in
                            messageBubble(entry).id(entry.id)
                        }
                        // Breathing room under the last line.
                        //
                        // Scrolled to the bottom, the final line sat flush
                        // against the edge and read as cut off — and with a
                        // descender or a second line arriving mid-stream it
                        // genuinely was. Scaled to the text size, because the
                        // amount that goes missing scales with it too.
                        Color.clear.frame(height: appearance.settings.fontSize)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GeometryReader { content in
                            Color.clear.preference(
                                key: TranscriptBottomKey.self,
                                value: content.frame(in: .named(Self.scrollSpace)).maxY
                            )
                        }
                    )
                }
                .coordinateSpace(name: Self.scrollSpace)
                .onPreferenceChange(TranscriptBottomKey.self) { contentBottom in
                    scrollPin.update(distanceFromBottom: contentBottom - viewport.size.height)
                }
                // Fires on streamed text too, not just new entries: a reply
                // grows inside one entry, and following only new entries would
                // leave the answer scrolling out of view as it arrives.
                .onChange(of: transcriptSignature) {
                    guard scrollPin.isFollowing, let last = secretary.transcript.last else { return }
                    // Unanimated, and measurements are muted while it settles:
                    // an animated scroll reports near-bottom positions all the
                    // way down, which re-latches following and drags the reader
                    // back even after they've scrolled away.
                    scrollPin.beginProgrammaticScroll()
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private static let scrollSpace = "transcript"

    /// Changes whenever anything visible changes — a new entry, or more text in
    /// the last one.
    private var transcriptSignature: String {
        "\(secretary.transcript.count):\(secretary.transcript.last?.text.count ?? 0)"
    }

    @ViewBuilder
    private func messageBubble(_ entry: TranscriptEntry) -> some View {
        let style = messageBubbleStyle(speaker: entry.speaker, kind: entry.kind)
        if !style.isBubble {
            activityRow(entry)
        } else {
            // Both markers come out before anything is laid out. The Secretary
            // already strips a loop block from a finished reply, but not from a
            // failed one, and a reply still streaming has yet to be stripped at
            // all — neither should put a fenced block on screen.
            let body = LoopBlock.parse(MessageChoices.parse(entry.text).body).body
            let parts = messageParts(of: MarkdownTableParser.segments(of: body))
            // Boxes within one turn sit closer together than turns do, but not
            // as close as they were: three boxes 5pt apart read as one striped
            // block rather than as three things.
            VStack(alignment: style.side == .trailing ? .trailing : .leading, spacing: 9) {
                // Both speakers are named above their boxes, not inside them:
                // the name is about the turn, and a reply split into three
                // boxes has one speaker, not three. Each header sits against
                // its own speaker's edge, so they mirror.
                if style.showsSpeakerName {
                    messageRow(style: style) {
                        header(entry, style: style).padding(.horizontal, 2)
                    }
                }
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    messageRow(style: style) {
                        partView(part, entry: entry, style: style, index: index)
                    }
                }
            }
        }
    }

    /// One box, with its own copy button in the top-right corner.
    ///
    /// Per box rather than per turn: a reply that split into prose, a table and
    /// a command is three things you might want separately, and the command on
    /// its own is the one you actually paste.
    @ViewBuilder
    private func partView(
        _ part: MessagePart,
        entry: TranscriptEntry,
        style: MessageBubbleStyle,
        index: Int
    ) -> some View {
        let box = BoxID(entry: entry.id, index: index)
        Group {
            switch part {
            case .prose(let segments):
                proseBubble(segments, style: style)
            case .block(let segment):
                // Its own message, with no bubble around it: a table and a
                // fenced block each already have a border, a fill and their own
                // sideways scroll, and a bubble around that is a second frame
                // that says nothing.
                blockView(segment)
            }
        }
        .overlay(alignment: .topTrailing) {
            if style.showsCopyButton, hoveredBox == box {
                boxButtons(text: copyText(of: part), box: box, entry: entry)
                    // Straddling the corner rather than sitting inside it: over
                    // the text, the button hid the end of the first line — and
                    // the one thing a copy button must not do is cover the words
                    // you are deciding whether to copy. The room it moves into is
                    // the gutter, which is empty by construction.
                    .offset(x: 10, y: -10)
            }
        }
        // Hover, not always: a button on every box at rest is three buttons in
        // a three-box answer, and none of them are what you came to read.
        .onHover { inside in
            if inside {
                hoveredBox = box
            } else if hoveredBox == box {
                hoveredBox = nil
            }
        }
    }

    /// Which box the pointer is over. One value, not a flag per box: the pointer
    /// is only ever in one place, and a flag each is a set of them that can all
    /// be true at once after a fast drag.
    struct BoxID: Equatable {
        let entry: UUID
        let index: Int
    }

    /// One line of the thread, tucked against this speaker's edge.
    ///
    /// The gutter is a minimum, not a fixed width: a short message keeps its
    /// bubble small and a long one grows into the rest of the row, which is what
    /// makes the thread read as a conversation rather than as two columns.
    private func messageRow<Content: View>(
        style: MessageBubbleStyle,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            if style.side == .trailing {
                Spacer(minLength: messageBubbleGutter(panelWidth: appearance.settings.chatWidth))
            }
            content()
            if style.side == .leading {
                Spacer(minLength: messageBubbleGutter(panelWidth: appearance.settings.chatWidth))
            }
        }
    }

    @ViewBuilder
    private func blockView(_ segment: TranscriptSegment) -> some View {
        switch segment {
        case .table(let table): tableView(table)
        case .code(let block): codeView(block)
        case .text(let body): Text(body)
        }
    }

    /// Who said it and when.
    ///
    /// `secondaryFontSize`: the header is there to be found, not read, and at
    /// message size it competes with the message.
    private func header(_ entry: TranscriptEntry, style: MessageBubbleStyle) -> some View {
        HStack(spacing: 5) {
            if style.isFailure {
                // Named as the app's own failure, not as something the persona
                // said. A warning in the persona's voice reads as the character
                // being unhelpful rather than as the tool being unreachable.
                Label("Couldn't reply", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: appearance.settings.secondaryFontSize, weight: .bold))
            } else {
                Text(speakerLabel(isMine: style.isMine, speakerName: entry.speakerName))
                    .font(.system(size: appearance.settings.secondaryFontSize, weight: .bold))
            }
            Text(MessageTime.label(for: entry.timestamp))
                .font(.system(size: appearance.settings.secondaryFontSize))
        }
        .foregroundStyle(style.isFailure ? Color.orange : Color.secondary)
    }

    /// Pin and copy, in that order left to right.
    ///
    /// One hover target for both, so moving between them can't make the pair
    /// flicker, and so the pointer leaving either one is the same event.
    private func boxButtons(text: String, box: BoxID, entry: TranscriptEntry) -> some View {
        HStack(spacing: 2) {
            pinButton(text: text, entry: entry)
            copyButton(text: text, box: box)
        }
        .onHover { inside in
            if inside {
                hoveredBox = box
            } else if hoveredBox == box {
                hoveredBox = nil
            }
        }
    }

    /// Pulls this box out into its own floating window, which then survives the
    /// chat being closed and the conversation moving on.
    ///
    /// The title is the speaker and the time, which is what tells two pinned
    /// panes apart in the menu — the body is already visible in the window.
    private func pinButton(text: String, entry: TranscriptEntry) -> some View {
        Button {
            onPin(
                InfoWindowSpec(
                    title: "\(speakerLabel(isMine: false, speakerName: entry.speakerName)) · \(MessageTime.label(for: entry.timestamp))",
                    body: text
                )
            )
        } label: {
            Image(systemName: "pin")
                .font(.system(size: appearance.settings.secondaryFontSize))
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Pin this box into its own window")
    }

    /// Copies this box, and says so.
    ///
    /// It sits over the corner of the box, so it is given the panel's own
    /// background behind it — over a line of text with no backing, an icon is
    /// unreadable and looks like a rendering fault.
    private func copyButton(text: String, box: BoxID) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            confirmCopy(of: box)
        } label: {
            // A tick in place of the icon is fine *here*, unlike in the header:
            // the button only exists while the pointer is on the box, so it
            // can't be left looking as though it went away.
            Image(systemName: copiedBox == box ? "checkmark" : "doc.on.doc")
                .font(.system(size: appearance.settings.secondaryFontSize))
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Copy this box")
        // The button hangs off the corner of the box, so the pointer reaching it
        // has left the box. Without this it would vanish on the way to being
        // clicked.
        .onHover { inside in
            if inside {
                hoveredBox = box
            } else if hoveredBox == box {
                hoveredBox = nil
            }
        }
    }

    /// Shows the tick, then takes it away again. Held only briefly: it says
    /// "that press worked", and a tick still sitting there ten minutes later
    /// says something else.
    private func confirmCopy(of box: BoxID) {
        copiedBox = box
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedBox == box { copiedBox = nil }
        }
    }

    /// The bubble itself: the message, in a rounded fill.
    ///
    /// The fill is the panel's own accent and secondary, not a new palette —
    /// the point of the change is the shape of the conversation, not a different
    /// look.
    private func proseBubble(
        _ segments: [TranscriptSegment],
        style: MessageBubbleStyle
    ) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if case .text(let body) = segment {
                        // AppKit-backed: SwiftUI's Text draws links but doesn't
                        // open them from a non-activating panel, and can't show
                        // a pointer or a hover underline over them.
                        // Capped at the width the text would take unwrapped, so
                        // a short message keeps a short bubble. Without the cap
                        // every bubble — "ok?" included — is as wide as the row
                        // allows, and the two sides read as columns rather than
                        // as a conversation. A long message asks for more than
                        // the row has and simply gets the row.
                        MessageTextView(
                            text: MessageMarkdown.attributed(body),
                            fontSize: appearance.settings.fontSize
                        )
                        .frame(
                            maxWidth: MessageTextView.naturalWidth(
                                MessageMarkdown.attributed(body),
                                fontSize: appearance.settings.fontSize
                            ),
                            alignment: .leading
                        )
                    }
                }
            }
            .padding(.horizontal, Self.bubbleTextInset)
            .padding(.vertical, 10)
            .background(bubbleFill(style), in: RoundedRectangle(cornerRadius: 12))
    }

    /// How far a bubble's text sits in from the bubble's edge — and, because a
    /// bubble starts at the edge of the thread, how far in from the thread the
    /// Secretary's words begin. The activity line is indented by the same amount
    /// so the two start in one column.
    private static let bubbleTextInset: Double = 14

    /// Yours is tinted with the accent, the Secretary's with the same neutral
    /// the rest of the panel uses. Both are faint: the text has to stay the
    /// loudest thing in the bubble.
    private func bubbleFill(_ style: MessageBubbleStyle) -> Color {
        if style.isFailure { return Color.orange.opacity(0.14) }
        return style.isMine ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12)
    }

    /// One setting, two buttons. A button that can't do anything is disabled
    /// rather than silently ignored, so reaching a limit reads as a limit.
    private func stepperRow(
        label: String,
        value: String,
        canDecrease: Bool,
        canIncrease: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        HStack(spacing: appearance.settings.panelSpacing) {
            Text(label)
                .font(.system(size: appearance.settings.footnoteFontSize))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: appearance.settings.footnoteFontSize, design: .monospaced))
                .frame(minWidth: 38, alignment: .trailing)
            Button("−", action: onDecrease)
                .buttonStyle(.bordered)
                .font(.system(size: appearance.settings.footnoteFontSize))
                .disabled(!canDecrease)
            Button("+", action: onIncrease)
                .buttonStyle(.bordered)
                .font(.system(size: appearance.settings.footnoteFontSize))
                .disabled(!canIncrease)
        }
    }

    /// A table laid out as a grid, scrolling sideways on its own when it's
    /// wider than the bubble. Cells use the body text size, not a smaller
    /// caption: a table is content, so it has to grow with +/- like the rest of
    /// the answer. Only the table scrolls — the conversation itself
    /// must not, or every wide answer would drag the whole thread off-screen.
    /// A fenced block, shown verbatim.
    ///
    /// Monospaced and scrolled sideways rather than wrapped: wrapping a line of
    /// JSON or a shell command puts a break where none exists, and the reader
    /// can no longer tell what would actually be typed. Same treatment as a
    /// wide table — the block scrolls, the conversation doesn't.
    private func codeView(_ block: CodeBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = block.language {
                Text(language)
                    .font(.system(size: appearance.settings.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 5)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                // Plain text, not `inlineMarkdown`: inside a code block an
                // asterisk is an asterisk, and a backtick is a backtick.
                Text(block.code)
                    .font(.system(size: appearance.settings.fontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private func tableView(_ table: MarkdownTable) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { _, cell in
                        Text(inlineMarkdown(cell))
                            .font(.system(size: appearance.settings.fontSize, weight: .bold))
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inlineMarkdown(cell))
                                .font(.system(size: appearance.settings.fontSize))
                        }
                    }
                }
            }
            // Cells size to their content; the scroll view provides the room.
            .fixedSize(horizontal: true, vertical: false)
            .padding(8)
            .textSelection(.enabled)
        }
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Cells routinely contain `**bold**`, `` `code` `` and links. Shared with
    /// the message body so a URL is clickable wherever it appears.
    private func inlineMarkdown(_ text: String) -> AttributedString {
        MessageMarkdown.attributed(text)
    }

    /// What happened, as bare text — no box, no border, no fill.
    ///
    /// It still has to read as the app talking about itself rather than as part
    /// of an answer, and now that is carried by the type alone: dimmer, smaller,
    /// with the "Working" label above it. A box did the same job louder, and
    /// stacked a frame inside a thread that is already made of frames.
    ///
    /// Left-aligned, and started at exactly the column the Secretary's words
    /// start at — the bubble's own horizontal padding, shared as a constant so
    /// the two can't drift a point apart and leave the thread looking ragged.
    private func activityRow(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Working", systemImage: "gearshape.2")
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
            Text(entry.text)
                .font(.system(size: appearance.settings.secondaryFontSize, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding(.leading, Self.bubbleTextInset)
        .padding(.trailing, messageBubbleGutter(panelWidth: appearance.settings.chatWidth))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var pendingDecisionView: some View {
        switch secretary.pendingDecision {
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
                    .foregroundStyle(.secondary)
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
                (leavesTheMachine ? Color.red : Color.orange).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8)
            )

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
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

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

    /// Grows a line at a time as the message gets longer, then stops and
    /// scrolls: five lines is about as much of the bubble as the input can take
    /// before the conversation above it stops being readable.
    /// The box spans the full width now, with the send affordance inside it
    /// rather than a button beside it.
    private var inputRow: some View {
        messageBox
    }

    /// The ↵'s point size, relative to the message text. Was 1.1 — 10% smaller
    /// now that it is drawn at full strength and no longer needs the size to be
    /// noticed.
    private var sendGlyphSize: Double { appearance.settings.fontSize * 1.1 * 0.9 }

    /// How much room the ↵ needs, glyph plus breathing space on either side.
    /// Derived from the glyph's own size rather than repeating the arithmetic:
    /// a lane that stopped matching the glyph would let a long line slide back
    /// under it.
    private var sendGlyphLane: Double { sendGlyphSize + 16 }

    /// Return, drawn rather than boxed: the keyboard is how this is sent, so the
    /// affordance says which key rather than offering a second, different thing
    /// to press. Still clickable for anyone who reaches for the mouse.
    ///
    /// Bottom-aligned, because the box grows downward as the message wraps and a
    /// centred glyph would drift away from the caret.
    private var sendGlyph: some View {
        Button(action: send) {
            Image(systemName: "return")
                .font(.system(size: sendGlyphSize, weight: .medium))
        }
        .buttonStyle(.plain)
        // Empty box: exactly the placeholder's colour, so the glyph sits at the
        // same weight as the "Ask the Secretary…" beside it. It used to be
        // dimmed to 35% of that and read as switched off.
        // `placeholderTextColor` and `secondaryLabelColor` are the same value
        // (black/white at 0.5 alpha) — naming the placeholder one says which
        // of the two this is matched to.
        .foregroundStyle(
            canSend ? AnyShapeStyle(Color.primary.opacity(0.75))
                    : AnyShapeStyle(Color(nsColor: .placeholderTextColor))
        )
        .disabled(!canSend)
        .help("Return to send")
        .padding(.trailing, 8)
        .padding(.bottom, 5)
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            Text("Settings")
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))

            Text("Claude API key")
                .font(.system(size: appearance.settings.footnoteFontSize))
                .foregroundStyle(.secondary)
            HStack(spacing: appearance.settings.panelSpacing) {
                SecureField(credentials.hasAPIKey ? "•••• stored in Keychain" : "sk-ant-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: appearance.settings.footnoteFontSize))
                Button("Save") { saveAPIKey() }
                    .buttonStyle(.bordered)
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if credentials.hasAPIKey {
                    Button("Clear") { clearAPIKey() }
                        .buttonStyle(.plain)
                        .font(.system(size: appearance.settings.footnoteFontSize))
                        .foregroundStyle(.secondary)
                }
            }
            Text("Stored only in your macOS Keychain — never logged or committed.")
                .font(.system(size: appearance.settings.hintFontSize))
                .foregroundStyle(.secondary)

            HStack(spacing: appearance.settings.panelSpacing * 1.6) {
                modelPicker
                effortPicker
            }
            .font(.system(size: appearance.settings.footnoteFontSize))
            Text("Change with /model <id> or /effort <level> in the chat.")
                .font(.system(size: appearance.settings.hintFontSize))
                .foregroundStyle(.secondary)

            browserPicker
            Text(
                "Reads pages in your Chrome, including sites you're signed in to. "
                + "Needs the Claude in Chrome extension. Clicking and typing still ask first."
            )
            .font(.system(size: appearance.settings.hintFontSize))
            .foregroundStyle(.secondary)
            // Two lines rather than one truncated one: the sentence about
            // reading signed-in sites is the part a person needs before they
            // switch this on, and "…" is where it was being cut.
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            stepperRow(
                label: "Text size",
                value: "\(Int(appearance.settings.fontSize))pt",
                canDecrease: appearance.settings.canDecreaseFontSize,
                canIncrease: appearance.settings.canIncreaseFontSize,
                onDecrease: appearance.decreaseFontSize,
                onIncrease: appearance.increaseFontSize
            )
            stepperRow(
                label: "Chat height",
                value: "\(Int(appearance.settings.chatHeight))pt",
                canDecrease: appearance.settings.canDecreaseHeight,
                canIncrease: appearance.settings.canIncreaseHeight,
                onDecrease: appearance.decreaseHeight,
                onIncrease: appearance.increaseHeight
            )
            Text("Or drag the grip in the corner away from the tail to size it freely — the tail stays on \(secretary.profile.displayName) either way.")
                .font(.system(size: appearance.settings.hintFontSize))
                .foregroundStyle(.secondary)

            if let settingsNote {
                Text(settingsNote)
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(appearance.settings.panelPadding)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            Text("Projects")
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))

            if registry.projects.isEmpty {
                Text("None registered. Add one to let me work in it.")
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .foregroundStyle(.secondary)
            }

            ForEach(registry.projects) { project in
                HStack(spacing: appearance.settings.panelSpacing) {
                    VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.25) {
                        Text(project.name).font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                        Text(project.path)
                            .font(.system(size: appearance.settings.hintFontSize, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                    Button {
                        addProjectNote = registry.removeReportingProblem(id: project.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            Button("Add project…") {
                addProjectNote = nil
                guard let project = ProjectPicker.promptForProject() else { return }
                addProjectNote = registry.addReportingProblem(project)
                // Adding a project mid-conversation is almost always a
                // correction to the question already asked, so the Secretary
                // re-scopes the workspace and runs it again.
                secretary.projectsDidChange()
            }
            .buttonStyle(.bordered)
            .font(.system(size: appearance.settings.footnoteFontSize))

            if let addProjectNote {
                Text(addProjectNote)
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(appearance.settings.panelPadding)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Checkboxes rather than a menu: unlike Model/Effort, this is a
    /// multi-select, and a `Menu` closes after every tap — wrong for checking
    /// several boxes in one visit.
    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            HStack {
                Text("Skills").font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                Spacer()
                Button {
                    secretary.refreshAvailableSkills()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Rescan for installed skills")
            }

            if secretary.availableSkills.isEmpty {
                Text("None found — checked ~/.claude/skills, this project's .claude/skills, and your enabled plugins.")
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .foregroundStyle(.secondary)
            }

            ForEach(secretary.availableSkills) { skill in
                Toggle(isOn: Binding(
                    get: { secretary.selectedSkills.contains(skill.id) },
                    set: { _ in secretary.toggleSkill(skill.id) }
                )) {
                    VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.25) {
                        Text(skill.name).font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                        if !skill.summary.isEmpty {
                            Text(skill.summary)
                                .font(.system(size: appearance.settings.hintFontSize))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }

            Text(
                secretary.selectedSkills.isEmpty
                    ? "Nothing checked — no restriction; I can use any installed skill."
                    : "Checked skills are a request, not a hard limit — I may still fall back if none of them fit."
            )
            .font(.system(size: appearance.settings.hintFontSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(appearance.settings.panelPadding)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    /// The open configuration section, held to a share of the window and given
    /// its own scroll.
    ///
    /// This is what makes the panel structurally incapable of overflowing. The
    /// surrounding `VStack` has exactly one flexible child — the transcript —
    /// and once that has shrunk to nothing, any further content simply spills
    /// past the bubble: the header goes off the top, the buttons off the
    /// bottom. Adding a row used to be enough to cross that line, so the fix
    /// cannot be a re-tuned constant. A section that can never be taller than
    /// its share, and scrolls when it wants to be, can never cross it at all.
    ///
    /// The share is a fraction of the real window height rather than "window
    /// minus the header, input and footer": those three grow with the text
    /// size, so any subtraction of them is a constant that goes stale the next
    /// time ⌘+ is pressed.
    @ViewBuilder
    private var openPanelSection: some View {
        if let panel = openPanel {
            ScrollView(.vertical) {
                switch panel {
                case .settings: settingsSection
                case .profile: ProfileSettingsView(profiles: profiles, appearance: appearance)
                case .projects: projectsSection
                case .skills: skillsSection
                }
            }
            .frame(maxHeight: appearance.settings.chatHeight * Self.panelHeightShare)
        }
    }

    /// Leaves the rest of the window — header, transcript, input row and the
    /// section buttons — the larger share at every text size.
    private static let panelHeightShare: Double = 0.55

    /// The section toggles grow with the text size like everything else in the
    /// panel: left at a fixed caption size they became unreadable specks next to
    /// 32pt replies. `controlSize` follows suit, or the button's own padding
    /// stays mini around text that isn't.
    private var footer: some View {
        HStack(spacing: 10) {
            ForEach(Array(// `isMirrored` means the tail is on the right, which is the usual
                // placement rather than the exceptional one.
                footerSlots(tailOnRight: layout.isMirrored).enumerated()), id: \.offset) { _, slot in
                switch slot {
                case .gap:
                    Spacer(minLength: 12)
                case .button(let button):
                    let panel = Panel(button)
                    // Still a toggle each, and clicking the open one still
                    // closes it — opening one closes whichever was open.
                    Toggle(
                        button.title,
                        isOn: Binding(
                            get: { openPanel == panel },
                            set: { openPanel = $0 ? panel : nil }
                        )
                    )
                }
            }
        }
        // Both ends of this row now hold a button, so the resize grip can no
        // longer be dodged by moving the buttons — it is kept clear by leaving
        // room at whichever bottom corner it is in.
        .padding(gripCorner.isLeading ? .leading : .trailing, gripCorner.isBottom ? 26 : 0)
        // Not `.toggleStyle(.button)`: an accent-tinted control loses its colour
        // whenever the window isn't key, and this window is never key. See
        // `PanelToggleStyle`.
        // Not `.toggleStyle(.button)`: an accent-tinted control loses its colour
        // whenever the window isn't key, and this window is never key. See
        // `PanelToggleStyle`, which keeps the bordered metrics and changes only
        // how "this one is open" is drawn.
        .toggleStyle(PanelToggleStyle(
            fontSize: appearance.settings.secondaryFontSize,
            controlSize: appearance.settings.fontSize > 16 ? .regular : .small
        ))
        .font(.system(size: appearance.settings.secondaryFontSize))
    }

    // MARK: - Actions

    /// What you've sent this session, oldest first.
    ///
    /// Read back out of the transcript rather than kept in a second list: the
    /// transcript already is the record, and a copy of it would be one more
    /// thing to keep in step. It also means recall covers exactly one session,
    /// which is what was asked for.
    private var sentMessages: [String] {
        secretary.transcript
            .filter { $0.speaker == .user && $0.kind == .message }
            .map(\.text)
    }

    /// Whether the arrows should act as history rather than move the caret.
    private var canRecall: Bool {
        !draft.contains("\n") && !sentMessages.isEmpty
    }

    /// The options the assistant is waiting on, if its latest message asked
    /// something. Only the latest: an older question has been overtaken.
    private var pendingChoices: [String] {
        guard machine.state == .idle,
              let last = secretary.transcript.last,
              last.speaker == .secretary, last.kind == .message
        else { return [] }
        return MessageChoices.parse(last.text).options
    }

    /// The question's answers, as a list you can walk with the arrow keys and
    /// take with Return — or simply click, since a keyboard-only control in a
    /// window you reach with the mouse would be a trap.
    @ViewBuilder
    private var choiceList: some View {
        let options = pendingChoices
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Button { pick(option) } label: {
                        HStack(alignment: .top, spacing: 6) {
                            // The caret marks the highlight for anyone who
                            // can't tell the tint apart from the background.
                            Text(index == choiceIndex ? "›" : " ")
                                .fontWeight(.bold)
                            Text(option)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: appearance.settings.fontSize))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(
                            index == choiceIndex ? Color.accentColor.opacity(0.22) : .clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // Says who the arrows currently belong to, because a key that
                // silently means two things is the part people get wrong.
                Text(
                    draft.isEmpty
                        ? "↑ ↓ to move · return to choose"
                        : "typing your own answer · ↑ ↓ recall sent messages"
                )
                .font(.system(size: appearance.settings.secondaryFontSize))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .onAppear { choiceIndex = 0 }
            // A new question replaces the old options in place, without the
            // list ever leaving the screen, so `onAppear` doesn't fire again.
            .onChange(of: options) { choiceIndex = 0 }
        }
    }

    /// Answering sends the option's own words, not "A" or "the second one":
    /// the model reads it as an ordinary reply, and the transcript records what
    /// was actually chosen.
    private func pick(_ option: String) {
        choiceIndex = 0
        draft = ""
        scrollPin.follow()
        secretary.submit(option)
    }

    /// Catches Up and Down before the text field turns them into caret
    /// movement.
    ///
    /// `.onKeyPress` was the obvious way and does not work here: Return
    /// arrives, the arrows never do, because the field consumes them as
    /// `moveUp:`/`moveDown:` first. Verified in the running app — the handler
    /// was in place and the box stayed empty. A local event monitor sees the
    /// key before the responder chain does, which is the only reliable point.
    private func startWatchingArrowKeys() {
        guard arrowKeyMonitor == nil else { return }
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.isDisjoint(with: [.command, .option, .control])
            else { return event }
            // Escape closes the panel, wherever the focus happens to be —
            // `.onExitCommand` was already declared and never fired on this
            // non-activating panel, which is why pressing it did nothing.
            if event.keyCode == 53 {
                onClose()
                return nil
            }
            // 126 is Up, 125 is Down. Which feature they belong to is decided
            // in one place — see `ArrowKeyOwner` — so the picker, history
            // recall and caret movement can never each take a turn at the same
            // keystroke.
            let options = pendingChoices
            switch ArrowKeyOwner.owner(
                hasChoices: !options.isEmpty,
                draft: draft,
                hasHistory: !sentMessages.isEmpty
            ) {
            case .choiceList:
                // Clamped at use: a second question can arrive while the list
                // is still up, and a highlight left pointing past a shorter
                // list would trap on Return.
                let highlighted = min(choiceIndex, options.count - 1)
                switch event.keyCode {
                case 126:
                    choiceIndex = max(0, highlighted - 1)
                    return nil
                case 125:
                    choiceIndex = min(options.count - 1, highlighted + 1)
                    return nil
                case 36:
                    pick(options[highlighted])
                    return nil
                default: return event
                }
            case .history:
                // Recall stays tied to the caret being in the box: it edits
                // what you are typing, so it needs you to be typing.
                guard messageBoxFocused else { return event }
                switch event.keyCode {
                case 126: return recallOlder() ? nil : event
                case 125: return recallNewer() ? nil : event
                default: return event
                }
            case .textCaret:
                return event
            }
        }
    }

    private func stopWatchingArrowKeys() {
        arrowKeyMonitor.map(NSEvent.removeMonitor)
        arrowKeyMonitor = nil
    }

    /// Steps back towards older messages. Returns whether it took the key.
    private func recallOlder() -> Bool {
        guard canRecall else { return false }
        let history = sentMessages
        switch recallIndex {
        case nil:
            stashedDraft = draft
            recallIndex = history.count - 1
        case let index? where index > 0:
            recallIndex = index - 1
        default:
            // Already at the oldest. Take the key anyway, so it stops here
            // rather than jumping the caret somewhere unexpected.
            return true
        }
        draft = recallIndex.map { history[$0] } ?? draft
        return true
    }

    /// Steps forward towards what you were typing.
    private func recallNewer() -> Bool {
        guard let index = recallIndex else { return false }
        let history = sentMessages
        if index + 1 < history.count {
            recallIndex = index + 1
            draft = history[index + 1]
        } else {
            recallIndex = nil
            draft = stashedDraft
        }
        return true
    }

    private func send() {
        let text = draft
        draft = ""
        // A sent message ends the walk: the next Up starts again from the end,
        // the way a shell behaves.
        recallIndex = nil
        stashedDraft = ""
        scrollPin.follow()
        secretary.submit(text)
    }

    private func saveAPIKey() {
        if let problem = credentials.saveAPIKeyReportingProblem(text: apiKeyDraft) {
            settingsNote = problem
        } else {
            apiKeyDraft = ""
            settingsNote = "API key saved."
        }
    }

    private func clearAPIKey() {
        settingsNote = credentials.clearAPIKeyReportingProblem() ?? "API key cleared."
    }

}

/// Carries the typed message's rendered height out of the field so the box can
/// be sized from it.
private struct MessageBoxHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}
