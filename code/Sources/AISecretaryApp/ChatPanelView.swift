import SwiftUI
import AssistantState
import ProjectRegistry
import SecretaryCore
import Credentials
import LLMProvider

/// The conversation panel, rendered as a manga-style speech bubble anchored to
/// the character. Shows the transcript, the input field, whatever decision the
/// Secretary is waiting on, and collapsible Settings/Projects/Debug sections.
struct ChatPanelView: View {
    let machine: AssistantStateMachine
    let secretary: Secretary
    let registry: ProjectRegistry
    let credentials: any CredentialStore
    let backendStatus: BackendStatus
    let layout: ChatBubbleLayout
    let onClose: () -> Void

    @State private var draft: String = ""
    @State private var showDebug = false
    @State private var showProjects = false
    @State private var showSettings = false
    @State private var lastRejection: String?
    @State private var addProjectNote: String?
    @State private var apiKeyDraft: String = ""
    @State private var settingsNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if backendStatus.needsOnboarding { onboardingCard }
            transcript
            pendingDecisionView
            inputRow
            if showSettings { settingsSection }
            if showProjects { projectsSection }
            if showDebug { debugSection }
            footer
        }
        .padding(18)
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
        .frame(width: 360, height: 520)
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

    private var header: some View {
        HStack(spacing: 6) {
            Text("AI Secretary")
                .font(.headline)
            Text(machine.state.description.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.trailing, 26)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if secretary.transcript.isEmpty {
                        Text(emptyTranscriptHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(secretary.transcript) { entry in
                        messageBubble(entry).id(entry.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: secretary.transcript.count) {
                if let last = secretary.transcript.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.speaker == .user ? "You" : "Secretary")
                .font(.caption2.bold())
                .foregroundStyle(entry.speaker == .user ? Color.accentColor : .secondary)
            Text(entry.text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    leavesTheMachine ? "Send to Claude?" : "Approval required",
                    systemImage: leavesTheMachine ? "paperplane.circle" : "lock.shield"
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

    private var inputRow: some View {
        HStack(spacing: 6) {
            TextField("Ask the Secretary…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
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
                Text("Model: \(secretary.model.displayName)")
                Text("Effort: \(secretary.effort.rawValue)")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            Text("Change with /model <id> or /effort <level> in the chat.")
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

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug — drive the state machine directly")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                debugButton("Listen") { send(.userBeganInput, "debug") }
                debugButton("Think") { send(.beginInterpreting, "debug") }
                debugButton("Work") { send(.beginExecuting, "debug") }
            }
            HStack(spacing: 6) {
                debugButton("Succeed") { send(.succeeded, "debug") }
                debugButton("Fail") { send(.failed, "debug") }
                debugButton("Ack") { send(.acknowledge, "debug") }
            }

            if let lastRejection {
                Text(lastRejection)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("Settings", isOn: $showSettings)
            Toggle("Projects", isOn: $showProjects)
            Toggle("Debug", isOn: $showDebug)
            Spacer()
        }
        .toggleStyle(.button)
        .controlSize(.mini)
        .font(.caption2)
    }

    // MARK: - Actions

    private func send() {
        let text = draft
        draft = ""
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

    private func debugButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            lastRejection = nil
            action()
        }
        .buttonStyle(.bordered)
        .font(.caption2)
    }

    private func send(_ event: AssistantEvent, _ reason: String) {
        if case .failure(let error) = machine.send(event, reason: reason) {
            lastRejection = "Rejected: \(error)"
        }
    }
}
