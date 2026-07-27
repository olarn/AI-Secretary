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
    @State private var showProjects = false
    @State private var showSettings = false
    @State private var showProfile = false
    @State private var addProjectNote: String?
    @State private var apiKeyDraft: String = ""
    @State private var settingsNote: String?
    @State private var scrollPin = TranscriptScrollPin()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if backendStatus.needsOnboarding { onboardingCard }
            transcript
            pendingDecisionView
            inputRow
            openSections
            footer
        }
        .padding(18)
        .controlSize(appearance.settings.controlSize)
        .frame(width: 360)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            SpeechBubbleShape(isMirrored: layout.isMirrored, isFlippedVertically: layout.isFlippedVertically)
                .fill(.regularMaterial)
        )
        .overlay(
            SpeechBubbleShape(isMirrored: layout.isMirrored, isFlippedVertically: layout.isFlippedVertically)
                .stroke(Color.primary.opacity(0.85), lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .onExitCommand(perform: onClose)
        .padding(layout.isFlippedVertically ? .top : .bottom, SpeechBubbleShape.defaultTailLength)
        .frame(width: 360, height: appearance.settings.chatHeight)
    }

    // MARK: - Sections

    /// The collapsible sections, scrolled only when they don't fit.
    ///
    /// At the default text size they never do need to — `ViewThatFits` takes the
    /// plain stack and the panel looks exactly as it always has. Turn the text up
    /// and the profile form alone is taller than the bubble, so the fallback
    /// gives it its own scroller rather than letting it push the composer and
    /// the footer off the bottom edge.
    @ViewBuilder
    private var openSections: some View {
        if showSettings || showProfile || showProjects {
            ViewThatFits(in: .vertical) {
                sectionStack
                ScrollView(.vertical) { sectionStack }
            }
            // On the container as well as the stack inside it: `ViewThatFits`
            // sizes itself to whichever child it picked, so without this an
            // empty Projects box shrinks the whole thing to the width of
            // "None registered." instead of filling the bubble.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sectionStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showSettings { settingsSection }
            if showProfile { ProfileSettingsView(profiles: profiles, appearance: appearance) }
            if showProjects { projectsSection }
        }
        // The sections used to sit directly in the panel's own stack, which is a
        // fixed width, so they filled it for free. Inside a scroll view they are
        // offered their ideal width instead — which for an empty Projects box is
        // just the width of "None registered.", leaving a box narrower than the
        // bubble. Ask for the full width back explicitly.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
                .font(appearance.settings.headingFont)
            Text("I work by driving your own copy of Claude Code, so it stays on your account. Two steps:")
                .font(appearance.settings.labelFont)
            Text("1. Install it — see claude.com/claude-code\n2. Run `claude` in Terminal once and sign in")
                .font(appearance.settings.labelFont.monospaced())
                .textSelection(.enabled)
            Text("Then reopen this panel. If it's installed somewhere unusual, I also check your login shell's PATH.")
                .font(appearance.settings.labelFont)
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
                secretary.selectModel(nil)
            } label: {
                Label(
                    "Your Claude Code default",
                    systemImage: secretary.isModelInherited ? "checkmark" : ""
                )
            }
            Divider()
            ForEach(ChatModel.known, id: \.id) { candidate in
                Button {
                    secretary.selectModel(candidate)
                } label: {
                    Label(
                        candidate.displayName,
                        systemImage: secretary.model == candidate ? "checkmark" : ""
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
                secretary.selectEffort(nil)
            } label: {
                Label(
                    "Your Claude Code default",
                    systemImage: secretary.isEffortInherited ? "checkmark" : ""
                )
            }
            Divider()
            ForEach(Effort.allCases, id: \.rawValue) { candidate in
                Button {
                    secretary.selectEffort(candidate)
                } label: {
                    Label(
                        candidate.rawValue,
                        systemImage: secretary.effort == candidate ? "checkmark" : ""
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

    /// Shows the real value either way; the dot marks one the app didn't pick,
    /// which can change if the user reconfigures Claude Code.
    private func settingLabel(_ title: String, value: String, inherited: Bool) -> some View {
        HStack(spacing: 3) {
            Text("\(title):").foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary)
            if inherited {
                Image(systemName: "circle.dashed")
                    .font(appearance.settings.glyphFont)
                    .foregroundStyle(.secondary)
            }
        }
        .font(appearance.settings.labelFont)
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
                .font(appearance.settings.titleFont)
            Text(machine.state.description.uppercased())
                .font(appearance.settings.labelFont.bold())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.trailing, 26)
    }

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
                                .font(appearance.settings.bodyFont)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(secretary.transcript) { entry in
                            messageBubble(entry).id(entry.id)
                        }
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
                    Array(MarkdownTableParser.segments(of: entry.text).enumerated()),
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
        ViewThatFits(in: .horizontal) {
            stepperLine(label: label, value: value, canDecrease: canDecrease,
                        canIncrease: canIncrease, onDecrease: onDecrease, onIncrease: onIncrease)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(appearance.settings.labelFont)
                    .foregroundStyle(.secondary)
                stepperLine(label: nil, value: value, canDecrease: canDecrease,
                            canIncrease: canIncrease, onDecrease: onDecrease, onIncrease: onIncrease)
            }
        }
    }

    private func stepperLine(
        label: String?,
        value: String,
        canDecrease: Bool,
        canIncrease: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            if let label {
                Text(label)
                    .font(appearance.settings.labelFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(value)
                .font(appearance.settings.labelFont.monospaced())
                .frame(minWidth: appearance.settings.size(38), alignment: .trailing)
            Button("−", action: onDecrease)
                .buttonStyle(.bordered)
                .font(appearance.settings.labelFont)
                .disabled(!canDecrease)
            Button("+", action: onIncrease)
                .buttonStyle(.bordered)
                .font(appearance.settings.labelFont)
                .disabled(!canIncrease)
        }
    }

    /// A table laid out as a grid, scrolling sideways on its own when it's
    /// wider than the bubble. Cells use the body text's size *and* its
    /// monospaced face: a table is content, so it has to grow with +/- like the
    /// rest of the answer, and at equal point sizes a proportional font reads
    /// smaller than the monospaced text around it — which made a table that was
    /// in fact scaling look as though it wasn't. Only the table scrolls — the
    /// conversation itself must not, or every wide answer would drag the whole
    /// thread off-screen.
    private func tableView(_ table: MarkdownTable) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { _, cell in
                        Text(inlineMarkdown(cell))
                            .font(appearance.settings.tableFont(bold: true))
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inlineMarkdown(cell))
                                .font(appearance.settings.tableFont(bold: false))
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
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    leavesTheMachine ? "Send to Claude?" : "Approval required",
                    systemImage: leavesTheMachine ? "paperplane.circle" : "lock.shield"
                )
                .font(appearance.settings.headingFont)
                Text(request.commandSummary)
                    .font(appearance.settings.labelFont.monospaced())
                Text("in \(request.project.name) · \(request.actionClass.humanDescription)")
                    .font(appearance.settings.labelFont)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Approve") { secretary.resolvePendingApproval(granted: true) }
                        .buttonStyle(.borderedProminent)
                    Button("Deny") { secretary.resolvePendingApproval(granted: false) }
                        .buttonStyle(.bordered)
                }
                .font(appearance.settings.labelFont)
            }
            .padding(10)
            .background(
                (leavesTheMachine ? Color.red : Color.orange).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8)
            )

        case .projectChoice(let candidates, _):
            VStack(alignment: .leading, spacing: 6) {
                Label("Choose a project", systemImage: "folder")
                    .font(appearance.settings.headingFont)
                ForEach(candidates) { candidate in
                    Button(candidate.name) { secretary.choose(project: candidate) }
                        .buttonStyle(.bordered)
                        .font(appearance.settings.labelFont)
                }
                Button("Cancel") { secretary.cancelPendingDecision() }
                    .buttonStyle(.plain)
                    .font(appearance.settings.labelFont)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

        case nil:
            EmptyView()
        }
    }

    private var inputRow: some View {
        HStack(spacing: 6) {
            TextField("Ask the Secretary…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(appearance.settings.labelFont)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(appearance.settings.headingFont)

            Text("Claude API key")
                .font(appearance.settings.labelFont)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                SecureField(credentials.hasAPIKey ? "•••• stored in Keychain" : "sk-ant-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(appearance.settings.labelFont)
                Button("Save") { saveAPIKey() }
                    .buttonStyle(.bordered)
                    .font(appearance.settings.labelFont)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if credentials.hasAPIKey {
                    Button("Clear") { clearAPIKey() }
                        .buttonStyle(.plain)
                        .font(appearance.settings.labelFont)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Stored only in your macOS Keychain — never logged or committed.")
                .font(appearance.settings.hintFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Side by side while they fit, stacked once they don't: both
            // pickers are .fixedSize(), so at large text they would otherwise
            // push the settings box wider than the bubble and truncate every
            // label in it down to "Text s…".
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    modelPicker
                    effortPicker
                }
                VStack(alignment: .leading, spacing: 4) {
                    modelPicker
                    effortPicker
                }
            }
            .font(appearance.settings.labelFont)
            Text("Change with /model <id> or /effort <level> in the chat.")
                .font(appearance.settings.hintFont)
                .foregroundStyle(.secondary)
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
            Text("Height only — the bubble's width is fixed so its tail stays on \(secretary.profile.displayName).")
                .font(appearance.settings.hintFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let settingsNote {
                Text(settingsNote)
                    .font(appearance.settings.hintFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Projects")
                .font(appearance.settings.headingFont)

            if registry.projects.isEmpty {
                Text("None registered. Add one to let me work in it.")
                    .font(appearance.settings.labelFont)
                    .foregroundStyle(.secondary)
            }

            ForEach(registry.projects) { project in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.name).font(appearance.settings.labelFont.bold())
                        Text(project.path)
                            .font(appearance.settings.hintFont.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                    Button {
                        try? registry.remove(id: project.id)
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
                    let added = (try? registry.add(project)) ?? false
                    if !added {
                        addProjectNote = "“\(project.name)” is already registered."
                    }
                }
            }
            .buttonStyle(.bordered)
            .font(appearance.settings.labelFont)

            if let addProjectNote {
                Text(addProjectNote)
                    .font(appearance.settings.hintFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Settings and Profile fill the bubble for free because each holds a
        // text field, which is greedy horizontally. Projects holds none, so with
        // nothing registered the box shrank to the width of "None registered."
        // and sat visibly narrower than the two beside it.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("Settings", isOn: $showSettings)
            Toggle("Profile", isOn: $showProfile)
            Toggle("Projects", isOn: $showProjects)
            Spacer()
        }
        .toggleStyle(.button)
        .controlSize(appearance.settings.chromeControlSize)
        .font(appearance.settings.labelFont)
    }

    // MARK: - Actions

    private func send() {
        let text = draft
        draft = ""
        scrollPin.follow()
        secretary.submit(text)
    }

    private func saveAPIKey() {
        do {
            try credentials.setAPIKey(apiKeyDraft.trimmingCharacters(in: .whitespaces))
            apiKeyDraft = ""
            settingsNote = "API key saved."
        } catch {
            settingsNote = "Could not save: \(error.localizedDescription)"
        }
    }

    private func clearAPIKey() {
        try? credentials.setAPIKey(nil)
        settingsNote = "API key cleared."
    }

}
