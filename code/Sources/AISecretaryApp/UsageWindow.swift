import AppKit
import SwiftUI
import LLMProvider
import SecretaryCore

@MainActor
@Observable
final class UsageRoster {
    var characters: [(name: String, secretary: Secretary)] = []
}

@MainActor
final class UsageWindow: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private let roster: UsageRoster
    private let plan: PlanUsageModel
    private var builtFor: ObjectIdentifier?

    init(roster: UsageRoster, backend: ChatBackend) {
        self.roster = roster
        self.plan = PlanUsageModel(backend: backend)
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func follow(_ appearance: Appearance) {
        guard let window else { return }
        window.appearance = appearance.colors.controlAppearance
        guard builtFor != ObjectIdentifier(appearance) else { return }
        window.contentView = NSHostingView(
            rootView: UsageView(roster: roster, appearance: appearance, plan: plan)
        )
        builtFor = ObjectIdentifier(appearance)
    }

    func toggle(using appearance: Appearance) {
        if isOpen { close() } else { show(using: appearance) }
    }

    func show(using appearance: Appearance) {
        NSApp.activate(ignoringOtherApps: true)

        plan.startPolling()

        if let window {
            follow(appearance)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 620),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Token Usage"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.appearance = appearance.colors.controlAppearance
        panel.contentView = NSHostingView(
            rootView: UsageView(roster: roster, appearance: appearance, plan: plan)
        )
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
        builtFor = ObjectIdentifier(appearance)
    }

    func close() {
        window?.orderOut(nil)
        plan.stopPolling()
    }

    func windowWillClose(_ notification: Notification) {
        plan.stopPolling()
    }
}

private struct UsageView: View {
    private var theme: Palette { appearance.colors }

    let roster: UsageRoster
    let appearance: Appearance
    @Bindable var plan: PlanUsageModel
    @State private var tick = Date()
    @State private var showPlan = true
    @State private var showWeekly = true
    @State private var showActivity = true
    @State private var showConversation = true

    private var usage: SessionUsage { totalUsage(roster.characters.map(\.secretary.sessionUsage)) }

    @ViewBuilder
    private var perCharacter: some View {
        if roster.characters.count > 1 {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(roster.characters.enumerated()), id: \.offset) { _, entry in
                    HStack {
                        Text(entry.name)
                            .foregroundStyle(theme.mutedText.color)
                        Spacer()
                        Text("\(entry.secretary.sessionUsage.turns) turns")
                            .foregroundStyle(theme.primaryText.color)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            content.padding(16)
        }
        .frame(minWidth: 300, minHeight: 320)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { tick = $0 }
        .themedWindow(theme)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            planSection
            Divider()
            sectionHeader(
                roster.characters.count > 1 ? "All conversations" : "This conversation",
                isExpanded: $showConversation
            )
            if !showConversation {
                EmptyView()
            } else if usage.turns == 0 {
                Text("Nothing used yet this session.")
                    .foregroundStyle(theme.mutedText.color)
            } else {
                contextBar
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    row("Input", usage.inputTokens)
                    row("Output", usage.outputTokens)
                    row("Cache write", usage.cacheWriteTokens)
                    row("Cache read", usage.cacheReadTokens)
                    row("Total", usage.totalTokens, emphasised: true)
                }
                perCharacter
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(UsageFormat.cost(usage.costUSD)) over \(usage.turns) turn\(usage.turns == 1 ? "" : "s")")
                    Text(UsageFormat.costNote)
                        .font(.system(size: appearance.settings.captionFontSize))
                        .foregroundStyle(theme.mutedText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: appearance.settings.secondaryFontSize))
    }

    @ViewBuilder
    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Plan usage limits", isExpanded: $showPlan) {
                if let name = plan.usage?.planName {
                    Text(name).foregroundStyle(theme.mutedText.color)
                }
            }

            if !showPlan {
                EmptyView()
            } else if let problem = plan.problem {
                Text(problem)
                    .foregroundStyle(theme.mutedText.color)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let usage = plan.usage {
                ForEach(Array(usage.session.enumerated()), id: \.offset) { _, limit in
                    limitRow(limit)
                }
                if !usage.weekly.isEmpty {
                    sectionHeader("Weekly limits", isExpanded: $showWeekly)
                        .padding(.top, 4)
                    if showWeekly {
                        ForEach(Array(usage.weekly.enumerated()), id: \.offset) { _, limit in
                            limitRow(limit)
                        }
                    }
                }
                if !usage.activity.isEmpty {
                    sectionHeader("What's driving it", isExpanded: $showActivity)
                        .padding(.top, 4)
                    if showActivity {
                        ForEach(Array(usage.activity.enumerated()), id: \.offset) { _, period in
                            activityRow(period)
                        }
                        Text(PlanUsage.activityNote)
                            .font(.system(size: appearance.settings.captionFontSize))
                            .foregroundStyle(theme.mutedText.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 6) {
                    Text("Last updated: \(UsageFormat.age(of: usage.checkedAt, now: tick))")
                        .font(.system(size: appearance.settings.captionFontSize))
                        .foregroundStyle(theme.mutedText.color)
                    Button { plan.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(plan.isRefreshing)
                    .help("Check again")
                    Spacer()
                }
                .padding(.top, 2)
            } else {
                Text(plan.isRefreshing ? "Checking…" : "Not checked yet.")
                    .foregroundStyle(theme.mutedText.color)
            }
        }
    }

    private func sectionHeader(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: max(8, appearance.settings.secondaryFontSize - 4), weight: .bold))
                    .foregroundStyle(theme.mutedText.color)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                Text(title)
                    .font(.system(size: appearance.settings.secondaryFontSize, weight: .semibold))
                trailing()
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded.wrappedValue ? "Hide this section" : "Show this section")
    }

    private func activityRow(_ period: PlanUsage.Activity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(period.period)
                Spacer()
                Text("\(UsageFormat.tokens(period.requests)) req · \(UsageFormat.tokens(period.sessions)) sessions")
                    .monospacedDigit()
                    .foregroundStyle(theme.mutedText.color)
            }
            ForEach(period.notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: appearance.settings.captionFontSize))
                    .foregroundStyle(theme.mutedText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func limitRow(_ limit: PlanUsage.Limit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(limit.name)
                Spacer()
                Text(limit.percentText).monospacedDigit().foregroundStyle(theme.mutedText.color)
            }
            ProgressView(value: limit.fraction)
                .tint(limit.fraction > 0.85 ? .orange : .accentColor)
            if let resets = limit.resetDescription(now: tick) {
                Text(resets)
                    .font(.system(size: appearance.settings.captionFontSize))
                    .foregroundStyle(theme.mutedText.color)
            } else if limit.fraction == 0 {
                Text("Not used yet")
                    .font(.system(size: appearance.settings.captionFontSize))
                    .foregroundStyle(theme.mutedText.color)
            }
        }
    }

    @ViewBuilder
    private var contextBar: some View {
        if let fraction = usage.contextFraction, let window = usage.contextWindow {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Context used")
                    Spacer()
                    Text(UsageFormat.percent(fraction)).monospacedDigit()
                }
                ProgressView(value: fraction)
                    .tint(fraction > 0.85 ? .orange : .accentColor)
                Text("\(UsageFormat.tokens(usage.lastTurnContextTokens)) of \(UsageFormat.tokens(window))")
                    .foregroundStyle(theme.mutedText.color)
                    .monospacedDigit()
            }
        }
    }

    private func row(_ label: String, _ value: Int, emphasised: Bool = false) -> some View {
        HStack {
            Text(label)
                .fontWeight(emphasised ? .semibold : .regular)
                .foregroundStyle(emphasised ? theme.primaryText.color : theme.mutedText.color)
            Spacer()
            Text(UsageFormat.tokens(value))
                .fontWeight(emphasised ? .semibold : .regular)
                .monospacedDigit()
        }
    }
}
