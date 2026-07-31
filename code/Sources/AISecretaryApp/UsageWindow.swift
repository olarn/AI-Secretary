import AppKit
import SwiftUI
import SecretaryCore

/// A small window showing what this conversation has spent, meant to be left
/// open beside the work.
///
/// A real titled window rather than a panel inside the chat, for two reasons:
/// the chat bubble is anchored to the character and closing it must not take
/// the figures away, and a number you are watching should be somewhere you can
/// park it. It floats above other apps like the rest of this app's windows, and
/// it follows the conversation live — `Secretary.sessionUsage` is observed, so a
/// window opened before the first question fills in as answers arrive.
@MainActor
final class UsageWindow: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private let secretary: Secretary
    private let appearance: Appearance

    init(secretary: Secretary, appearance: Appearance) {
        self.secretary = secretary
        self.appearance = appearance
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func toggle() {
        if isOpen { close() } else { show() }
    }

    func show() {
        // Nothing in this app takes focus by itself, so without activating, the
        // window opens behind whatever is in front and reads as "nothing
        // happened" — the same trap the About window and the pickers hit.
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 260),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
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
        panel.contentView = NSHostingView(
            rootView: UsageView(secretary: secretary, appearance: appearance)
        )
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }

    func close() {
        window?.orderOut(nil)
    }
}

/// The contents. Deliberately plain: four counts, a context bar and the caveat
/// about what the dollar figure is.
private struct UsageView: View {
    @Bindable var secretary: Secretary
    let appearance: Appearance

    private var usage: SessionUsage { secretary.sessionUsage }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if usage.turns == 0 {
                Text("Nothing used yet this session.")
                    .foregroundStyle(.secondary)
            } else {
                contextBar
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    row("Input", usage.inputTokens)
                    row("Output", usage.outputTokens)
                    row("Cache write", usage.cacheWriteTokens)
                    row("Cache read", usage.cacheReadTokens)
                    GridRow {
                        Text("Total").fontWeight(.semibold)
                        Text(UsageFormat.tokens(usage.totalTokens))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .gridColumnAlignment(.trailing)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(UsageFormat.cost(usage.costUSD)) over \(usage.turns) turn\(usage.turns == 1 ? "" : "s")")
                    Text(UsageFormat.costNote)
                        .font(.system(size: max(9, appearance.settings.secondaryFontSize - 2)))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: appearance.settings.secondaryFontSize))
        .padding(16)
        .frame(minWidth: 260, minHeight: 200)
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
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func row(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(UsageFormat.tokens(value))
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }
}
