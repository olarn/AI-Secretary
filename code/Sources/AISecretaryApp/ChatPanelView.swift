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

    @State private var draft: String = ""
    /// Which configuration section is open, if any.
    ///
    /// One selection rather than three independent flags, because three
    /// independent flags allow all three sections open at once — which is how
    /// the panel came to be taller than the window it lives in, pushing the
    /// transcript off the top and the Save button off the bottom. The state
    /// simply isn't representable now.
    enum Panel: String, Identifiable {
        case settings, profile, projects
        var id: String { rawValue }
        var title: String {
            switch self {
            case .settings: return "Settings"
            case .profile: return "Profile"
            case .projects: return "Projects"
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
        // Both control clusters live along the top, in opposite corners, and
        // trade places when the bubble is mirrored so each stays on the same
        // side of the character as before.
        //
        // Attached inside the body rather than to the outer frame: the outer
        // frame includes the strip reserved for the tail, and anything aligned
        // to the bottom of it would sit in the tail, outside the bubble.
        .overlay(alignment: buttonsOnLeading ? .topLeading : .topTrailing) { windowButtons }
        .overlay(alignment: buttonsOnLeading ? .topTrailing : .topLeading) { resizeGrip }
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

    /// Which top corner each cluster gets. The button row sits on the tail's
    /// side and the grip opposite it, so both follow the bubble when it mirrors
    /// and neither ever lands on the other.
    ///
    /// This only moves them. What the buttons *do* is decided elsewhere and
    /// doesn't depend on where they are: widening still steps, restoring still
    /// goes straight to the default, and the drag still follows the direction
    /// the bubble grows rather than the grip's own corner.
    private var buttonsOnLeading: Bool { !layout.isMirrored }

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
            TextField("Ask the Secretary…", text: $draft, axis: .vertical)
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
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            // The glyph points along ↖↘, which is the grip's own diagonal in the
            // top-left corner; in the top-right it has to point ↗↙ instead.
            .rotationEffect(.degrees(buttonsOnLeading ? 90 : 0))
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
    /// be in — the two have been on both sides of each other, and only the
    /// layout says which edges are free to move.
    ///
    /// Horizontally they agree in any case: the grip sits opposite the tail, on
    /// the corner the bubble grows into, so dragging it "the way the bubble
    /// extends" and the usual corner-handle reading of "away from the bubble"
    /// are the same drag. Vertically they agree in the usual position too, where
    /// the top edge is the one that moves and the grip rides along with it. They
    /// part only when the bubble has been flipped below the character: the tail
    /// is then on top, so the top edge is pinned and the bubble grows downward
    /// while the grip stays where it is. The drag follows the growth, which
    /// means dragging down through a grip that doesn't follow the cursor.
    private func resize(to pointer: CGPoint) {
        let settings = appearance.settings
        let origin = dragOrigin ?? DragOrigin(
            pointer: pointer,
            width: settings.chatWidth,
            height: settings.chatHeight
        )
        if dragOrigin == nil { dragOrigin = origin }

        let growsRight: Double = layout.isMirrored ? -1 : 1
        // Screen coordinates point up, so this is already "up is taller" unless
        // the bubble sits below the character and grows downward instead.
        let growsUp: Double = layout.isFlippedVertically ? -1 : 1
        appearance.resizeChat(
            width: origin.width + (pointer.x - origin.pointer.x) * growsRight,
            height: origin.height + (pointer.y - origin.pointer.y) * growsUp
        )
    }

    /// Where the drag started, so every step is measured from one fixed point
    /// rather than accumulated.
    struct DragOrigin {
        let pointer: CGPoint
        let width: Double
        let height: Double
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
        VStack(alignment: .leading, spacing: 6) {
            Label("Claude Code isn't set up", systemImage: "exclamationmark.triangle")
                .font(.caption.bold())
            Text("I work by driving your own copy of Claude Code, so it stays on your account. Two steps:")
                .font(.caption2)
            Text("1. Install it — see claude.com/claude-code\n2. Run `claude` in Terminal once and sign in")
                .font(.caption2.monospaced())
                .textSelection(.enabled)
            Text("Then reopen this panel. If it's installed somewhere unusual, I also check your login shell's PATH.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
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
        .font(.caption2)
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
        HStack(spacing: 3) {
            Text("\(title):").foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary)
            if inherited {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }

    /// What the assistant is doing right now.
    ///
    /// Note this is activity, not reasoning: Claude Code returns thinking
    /// blocks with no text (the raw chain of thought isn't exposed on this
    /// model family), so there is nothing to render for the thought itself.
    /// Which tool it reached for, and with what, is the part that exists.
    private var header: some View {
        HStack(spacing: 6) {
            Text(secretary.profile.displayName)
                .font(.headline)
            Text(machine.state.description.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            loopBadge
            Spacer()
        }
        // Both top corners are occupied — the resize grip in one, the
        // widen/restore/close row in the other — so the title drops below them
        // rather than being inset past them. Inset was the first attempt and it
        // moved the name around as the bubble mirrored; the title now stays
        // flush left at every size and on either side.
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
                    VStack(alignment: .leading, spacing: 8) {
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
        switch entry.kind {
        case .activity: activityBubble(entry)
        case .message:
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.speaker == .user ? "You" : secretary.profile.displayName)
                    .font(.system(size: appearance.settings.secondaryFontSize, weight: .bold))
                    .foregroundStyle(entry.speaker == .user ? Color.accentColor : .secondary)
                ForEach(
                    // Both markers come out before anything is laid out. The
                    // Secretary already strips a loop block from a finished
                    // reply, but not from a failed one, and a reply still
                    // streaming has yet to be stripped at all — neither should
                    // put a fenced block on screen.
                    Array(
                        MarkdownTableParser
                            .segments(of: LoopBlock.parse(MessageChoices.parse(entry.text).body).body)
                            .enumerated()
                    ),
                    id: \.offset
                ) { _, segment in
                    switch segment {
                    case .text(let body):
                        // AppKit-backed: SwiftUI's Text draws links but doesn't
                        // open them from a non-activating panel, and can't show
                        // a pointer or a hover underline over them.
                        MessageTextView(
                            text: MessageMarkdown.attributed(body),
                            fontSize: appearance.settings.fontSize
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    case .table(let table):
                        tableView(table)
                    case .code(let block):
                        codeView(block)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption2.monospaced())
                .frame(minWidth: 38, alignment: .trailing)
            Button("−", action: onDecrease)
                .buttonStyle(.bordered)
                .font(.caption2)
                .disabled(!canDecrease)
            Button("+", action: onIncrease)
                .buttonStyle(.bordered)
                .font(.caption2)
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

    /// Sits in the conversation in order, but deliberately doesn't look like
    /// one: a bordered, dimmer box so it reads as "here's what happened" rather
    /// than as part of the answer.
    private func activityBubble(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Working", systemImage: "gearshape.2")
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(entry.text)
                .font(.system(size: appearance.settings.secondaryFontSize, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        )
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
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    inBrowser
                        ? "Act in your browser?"
                        : (leavesTheMachine ? "Send to Claude?" : "Approval required"),
                    systemImage: inBrowser
                        ? "globe"
                        : (leavesTheMachine ? "paperplane.circle" : "lock.shield")
                )
                .font(.caption.bold())
                Text(request.commandSummary)
                    .font(.caption.monospaced())
                Text("in \(request.project.name) · \(request.actionClass.humanDescription)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Approve") { secretary.resolvePendingApproval(granted: true) }
                        .buttonStyle(.borderedProminent)
                    Button("Deny") { secretary.resolvePendingApproval(granted: false) }
                        .buttonStyle(.bordered)
                }
                .font(.caption)
            }
            .padding(10)
            .background(
                (leavesTheMachine ? Color.red : Color.orange).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8)
            )

        case .projectChoice(let candidates, _):
            VStack(alignment: .leading, spacing: 6) {
                Label("Choose a project", systemImage: "folder")
                    .font(.caption.bold())
                ForEach(candidates) { candidate in
                    Button(candidate.name) { secretary.choose(project: candidate) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
                Button("Cancel") { secretary.cancelPendingDecision() }
                    .buttonStyle(.plain)
                    .font(.caption2)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

        case nil:
            EmptyView()
        }
    }

    /// Grows a line at a time as the message gets longer, then stops and
    /// scrolls: five lines is about as much of the bubble as the input can take
    /// before the conversation above it stops being readable.
    private var inputRow: some View {
        // Centred on the box rather than sitting on its baseline, and sized from
        // the text: bottom-aligned against a box whose height now changes with
        // both the message and the text size, the button never lined up with
        // anything.
        HStack(alignment: .center, spacing: 6) {
            messageBox
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
            }
            .font(.system(size: appearance.settings.fontSize * 1.5))
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.caption.bold())

            Text("Claude API key")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                SecureField(credentials.hasAPIKey ? "•••• stored in Keychain" : "sk-ant-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Save") { saveAPIKey() }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if credentials.hasAPIKey {
                    Button("Clear") { clearAPIKey() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Stored only in your macOS Keychain — never logged or committed.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                modelPicker
                effortPicker
            }
            .font(.caption2)
            Text("Change with /model <id> or /effort <level> in the chat.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            browserPicker
            Text(
                "Reads pages in your Chrome, including sites you're signed in to. "
                + "Needs the Claude in Chrome extension. Clicking and typing still ask first."
            )
            .font(.system(size: 9))
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
            Text("Or drag the grip in the top corner to size it freely — the tail stays on \(secretary.profile.displayName) either way.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            if let settingsNote {
                Text(settingsNote)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Projects")
                .font(.caption.bold())

            if registry.projects.isEmpty {
                Text("None registered. Add one to let me work in it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(registry.projects) { project in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.name).font(.caption2.bold())
                        Text(project.path)
                            .font(.system(size: 9).monospaced())
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
                if let project = ProjectPicker.promptForProject() {
                    addProjectNote = registry.addReportingProblem(project)
                }
            }
            .buttonStyle(.bordered)
            .font(.caption2)

            if let addProjectNote {
                Text(addProjectNote)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
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
            // Still a toggle each, and clicking the open one still closes it —
            // only now opening one closes whichever was open.
            ForEach([Panel.settings, .profile, .projects]) { panel in
                Toggle(
                    panel.title,
                    isOn: Binding(
                        get: { openPanel == panel },
                        set: { openPanel = $0 ? panel : nil }
                    )
                )
            }
            Spacer()
        }
        .toggleStyle(.button)
        .controlSize(appearance.settings.fontSize > 16 ? .regular : .small)
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
