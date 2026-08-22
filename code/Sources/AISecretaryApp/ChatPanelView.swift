import AppKit
import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import LLMProvider

struct ChatPanelView: View {
    let machine: AssistantStateMachine
    let secretary: Secretary
    let registry: ProjectRegistry
    let backendStatus: BackendStatus
    let vendorStatus: VendorStatus
    let appearance: Appearance
    let profiles: ProfileLibrary
    let profileID: UUID
    let layout: ChatBubbleLayout
    let onClose: () -> Void
    let onPin: (InfoWindowSpec) -> Void

    var theme: Palette { appearance.colors }

    @State var draft: String = ""
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
    @State var draftHeight: Double = 0
    @State var recallIndex: Int?
    @State var stashedDraft = ""
    @FocusState var messageBoxFocused: Bool
    @State var arrowKeyMonitor: Any?
    @State var scrollMonitor: Any?
    @State var partsCache = MessagePartsCache()
    @State var pointerOverTranscript = false
    @State var choiceIndex = 0
    @State var hover = BoxHover()
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
        .onChange(of: layout.focusRequests) {
            if draft.isEmpty { messageBoxFocused = true }
        }
        .frame(width: appearance.settings.chatWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(bubbleSurface)
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { secretary.attach(url) }
            return !urls.isEmpty
        } isTargeted: { droppingFile = $0 }
        .overlay {
            if !appearance.settings.liquidGlass {
                SpeechBubbleShape(isMirrored: layout.isMirrored, isFlippedVertically: layout.isFlippedVertically)
                    .stroke(theme.panelBorder.color, lineWidth: theme.panelBorderWidth)
            }
        }
        .overlay(alignment: buttonsOnLeading ? .topLeading : .topTrailing) { windowButtons }
        .overlay(alignment: gripAlignment) { resizeGrip }
        .padding(layout.isFlippedVertically ? .top : .bottom, SpeechBubbleShape.defaultTailLength)
        .frame(width: appearance.settings.chatWidth, height: appearance.settings.chatHeight)
    }

    @ViewBuilder
    private var bubbleSurface: some View {
        let shape = SpeechBubbleShape(
            isMirrored: layout.isMirrored, isFlippedVertically: layout.isFlippedVertically
        )
        if appearance.settings.liquidGlass {
            ZStack {
                shape.fill(theme.ground.color(opacity: 0.15))
                Color.clear.glassEffect(.regular, in: shape)
            }
        } else {
            shape.fill(theme.ground.color)
        }
    }

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

    private var buttonsOnLeading: Bool { !layout.isMirrored }

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

    private static let closeButtonSize: Double = 18 * 0.9
    private static let widthButtonSize: Double = 18 * 0.7

    private var resizeGrip: some View {
        Image(systemName: gripCorner.glyphName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(theme.mutedText.color)
            .padding(10)
            .contentShape(Rectangle())
            .help("Drag to resize")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in resize(to: NSEvent.mouseLocation) }
                    .onEnded { _ in dragOrigin = nil }
            )
    }

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

    private var approvalButtons: some View {
        HStack(spacing: appearance.settings.panelSpacing * 1.3) {
            ForEach(secretary.offeredApprovalAnswers, id: \.rawValue) { answer in
                Button(answer.title) { secretary.resolvePendingApproval(answer: answer) }
                    .buttonStyle(.bordered)
                    .tint(answer == .once ? theme.accent.color : theme.primaryText.color)
            }
        }
        .font(.system(size: appearance.settings.footnoteFontSize))
    }

    @ViewBuilder
    private var pendingDecisionView: some View {
        switch secretary.awaitingDecision {
        case .approval(let request, _):
            let leavesTheMachine = request.actionClass != .readOnly
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
                approvalButtons
                if secretary.offeredApprovalAnswers.contains(.always) {
                    Text("Always keeps this for \(request.project.name) after you quit. Nothing else is remembered.")
                        .font(.system(size: appearance.settings.hintFontSize))
                        .foregroundStyle(theme.mutedText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(appearance.settings.panelPadding)
            .background(
                (leavesTheMachine ? theme.dangerFill : theme.warningFill).color,
                in: RoundedRectangle(cornerRadius: 8)
            )

        case .interruption(let text, _, let freeCharacters):
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
                Label("I'm still on the last one", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                Text(text)
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .foregroundStyle(theme.mutedText.color)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: appearance.settings.panelSpacing * 1.3) {
                    Button(CardChoice.waitItsTurn) { secretary.resolveInterruption(.wait) }
                        .buttonStyle(.borderedProminent)
                    Button(CardChoice.replaceRunning) {
                        secretary.resolveInterruption(.replace)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.system(size: appearance.settings.footnoteFontSize))
                if !freeCharacters.isEmpty {
                    Menu(CardChoice.giveItToSomeone) {
                        ForEach(freeCharacters) { who in
                            Button(who.name) {
                                secretary.resolveInterruption(.delegate(to: who))
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.system(size: appearance.settings.footnoteFontSize))
                }
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
                Button(CardChoice.cancel) { secretary.cancelPendingDecision() }
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
                Text(
                    request.connectsBrowser
                        ? "Connects Chrome, then acts as you on \(request.host) for this conversation"
                        : "Acts as you on \(request.host) for this conversation"
                )
                .font(.system(size: appearance.settings.footnoteFontSize))
                .foregroundStyle(theme.mutedText.color)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: appearance.settings.panelSpacing * 1.3) {
                    Button(CardChoice.goAhead) { secretary.resolveWebTask(granted: true) }
                        .buttonStyle(.borderedProminent)
                    Button(CardChoice.notThisOne) { secretary.resolveWebTask(granted: false) }
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
            .id(plan.fingerprint)

        case nil:
            EmptyView()
        }
    }

}
