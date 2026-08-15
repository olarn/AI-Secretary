import AppKit
import SwiftUI
import LLMProvider
import SecretaryCore

/// Who is on the desktop, for the one usage window.
///
/// Observable rather than a snapshot taken when the window opens: the window is
/// built once and kept, so a character created while it is up would otherwise
/// never appear in it.
@MainActor
@Observable
final class UsageRoster {
    var characters: [(name: String, secretary: Secretary)] = []
}

/// A real titled window rather than a panel inside the chat, for two reasons:
/// the chat bubble is anchored to the character and closing it must not take
/// the figures away, and a number you are watching should be somewhere you can
/// park it. It floats above other apps like the rest of this app's windows, and
/// it follows the conversation live — `Secretary.sessionUsage` is observed, so a
/// window opened before the first question fills in as answers arrive.
@MainActor
final class UsageWindow: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private let roster: UsageRoster
    private let plan: PlanUsageModel
    /// Whose look the contents were built from. This window belongs to the app
    /// rather than to a character, so it borrows one — and has to notice when
    /// the character it borrowed from is no longer the one being worked with.
    private var builtFor: ObjectIdentifier?

    init(roster: UsageRoster, backend: ChatBackend) {
        self.roster = roster
        self.plan = PlanUsageModel(backend: backend)
    }

    var isOpen: Bool { window?.isVisible ?? false }

    /// Puts this window in one character's look and keeps it there.
    ///
    /// Two things have to move together and were split before, which showed as
    /// a window wearing half of each: the AppKit control appearance, which a
    /// SwiftUI body cannot return, and the hosting view, which observes the
    /// `Appearance` it was built with and so never notices a *different*
    /// character being focused. Re-lighting one without rebuilding the other
    /// gave a light title bar over a dark body.
    ///
    /// Cheap to call often: the rebuild only happens when the character has
    /// actually changed.
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
        // Nothing in this app takes focus by itself, so without activating, the
        // window opens behind whatever is in front and reads as "nothing
        // happened" — the same trap the About window and the pickers hit.
        NSApp.activate(ignoringOtherApps: true)

        plan.startPolling()

        if let window {
            follow(appearance)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 620),
            // Resizable as well: the content is scrolled, but someone with room
            // on screen should be able to see all of it at once.
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Token Usage"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Left restorable, AppKit can reopen it on launch on its own; what is on
        // screen is this app's decision. Same rule as the character panel.
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

    /// Closing by the window's own button goes through here, not `close()`.
    func windowWillClose(_ notification: Notification) {
        plan.stopPolling()
    }
}

/// The contents. Deliberately plain: four counts, a context bar and the caveat
/// about what the dollar figure is.
private struct UsageView: View {
    /// This window sets the palette rather than inheriting one: it is a root,
    /// not a view inside the chat panel.
    private var theme: Palette { appearance.colors }

    let roster: UsageRoster
    let appearance: Appearance
    @Bindable var plan: PlanUsageModel
    /// Re-read every half minute so the relative times move on their own. The
    /// figures behind them are polled far less often; this only re-renders the
    /// words, which would otherwise sit at "Resets in 18 min" for an hour.
    @State private var tick = Date()
    /// Which sections are open. Held here rather than persisted: the window is
    /// built once and kept, so a fold survives closing and reopening within a
    /// run, which is as long as anyone is watching a live gauge.
    @State private var showPlan = true
    @State private var showWeekly = true
    @State private var showActivity = true
    @State private var showConversation = true

    /// Everybody's figures added together. The window is at the root of the
    /// menu because the bill is the machine's, but each character keeps her own
    /// session, so the total is made here rather than read off one of them.
    private var usage: SessionUsage { totalUsage(roster.characters.map(\.secretary.sessionUsage)) }

    /// Who spent what, shown only when there is more than one of them —
    /// a breakdown of one row is just the total again.
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
        // Scrolled, because the content grows: plan limits, however many weekly
        // windows the account has, the activity block, and the token table. A
        // fixed height that fits today gets cut off the next time Claude Code
        // adds a line — which it did, and the last row went off the bottom.
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
            // Named for what it now adds up. It was "This conversation" while
            // there was one; with several characters the figures are every
            // live session together, and calling that a conversation would be
            // a number that matches nothing on screen.
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

    /// What is left of the subscription's allowance, laid out like the Usage
    /// panel in the Claude app — session first, then the weekly windows — since
    /// that is the arrangement the user already reads.
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

    /// A heading that folds what is under it. The whole row is the target, not
    /// just the chevron — a 10pt triangle is a poor thing to have to hit, and
    /// the title is right there.
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

    /// How much work went through this machine in a stretch, and what shape it
    /// had. The counts answer "why is the bar there"; the notes say what kind of
    /// work drove it.
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

    /// One limit: name, bar, percentage, and when it rolls over. A model-specific
    /// window at zero says so in words rather than showing an empty bar and a
    /// reset time it does not have.
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

    /// The one figure worth watching while working: how close this conversation
    /// is to filling the model's context.
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

    /// Label left, number hard against the right edge — a `Grid` sizes itself to
    /// its contents, so its right column floated in the middle of the window
    /// instead of lining up with the percentages above it.
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
