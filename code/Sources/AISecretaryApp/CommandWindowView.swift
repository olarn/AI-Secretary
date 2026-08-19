import SwiftUI
import SecretaryCore

/// The command window: tick who should listen, type once, everyone ticked
/// gets it. Spotlight-shaped — one borderless rounded slab in the middle of
/// the screen — with the character list above the box, the same growing
/// message box the chat uses, and the red line under it when nothing can go.
struct CommandWindowView: View {
    @Bindable var model: CommandCenter
    let appearance: Appearance
    /// Starts the native window drag. The *detection* lives here as a gesture
    /// because neither AppKit route sees the click on this window —
    /// `isMovableByWindowBackground` never fires (the hosting view answers the
    /// background hit-test for every point) and the window's own `mouseDown`
    /// never runs (SwiftUI consumes the click first); both driven 2026-08-19.
    /// The *movement* is `performDrag`, not per-event `setFrameOrigin`: moving
    /// the window from gesture callbacks stuttered visibly — the owner called
    /// it out the moment they tried it — while the native drag loop is the
    /// same one every title bar uses.
    let beginWindowDrag: () -> Void
    /// Hides the window — the ✕, same meaning as Esc: sessions keep running.
    let hideWindow: () -> Void
    /// Told the slab's rendered height, so the window can follow it. Sizing
    /// the hosting view by `preferredContentSize` instead left every
    /// `DragGesture` in the window dead — driven 2026-08-19: chips clicked
    /// fine, the drag never fired once, and the chat panel's grip (a plain
    /// framed hosting view) dragged fine under the same synthetic events.
    let contentHeightChanged: (Double) -> Void

    @State private var draft = ""
    @State private var draftHeight: Double = 0
    @State private var droppingFile = false
    @FocusState private var boxFocused: Bool

    private var theme: Palette { appearance.colors }

    var body: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            characterRow
            if droppingFile { dropHint }
            if !model.droppedFiles.isEmpty { fileRow }
            messageBox
            if let error = model.errorText {
                Text(error)
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .foregroundStyle(theme.danger.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(appearance.settings.panelPadding * 1.5)
        .frame(width: model.slabWidth, alignment: .leading)
        .background {
            // The gesture rides on the fill itself, the way the resize grip
            // rides on its glyph: hit-testing reaches the background exactly
            // where no control in front claims the point, which is what "drag
            // by the background" means.
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.ground.color)
                .gesture(windowDrag)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.panelBorder.color, lineWidth: theme.panelBorderWidth))
        .overlay(alignment: .topTrailing) { closeButton.padding(6) }
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        // The whole slab takes the drop, same as the chat bubble — naming one
        // rectangle as the target is the belief the chat's drop area undid.
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach { model.attach($0) }
            return !urls.isEmpty
        } isTargeted: { droppingFile = $0 }
        .animation(.easeOut(duration: 0.12), value: droppingFile)
        .onChange(of: model.focusRequests) { boxFocused = true }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SlabHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SlabHeightKey.self) { contentHeightChanged($0) }
        .environment(\.palette, theme)
        .foregroundStyle(theme.primaryText.color)
        .tint(theme.accent.color)
    }

    /// Who is listening. Every character on the desktop, tick by click; a
    /// command only ever reaches the ticked.
    private var characterRow: some View {
        HStack(spacing: appearance.settings.panelSpacing) {
            ForEach(model.roster(), id: \.id) { card in
                characterChip(card)
            }
            Spacer(minLength: 0)
        }
    }

    private func characterChip(_ card: CharacterCard) -> some View {
        let ticked = model.selected.contains(card.id)
        return Button {
            model.toggle(card.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                Text(card.name)
            }
            .font(.system(size: appearance.settings.footnoteFontSize, weight: ticked ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(ticked ? theme.accentFill.color : theme.chipFill.color, in: Capsule())
            .overlay(Capsule().stroke(ticked ? theme.accent.color : theme.hairline.color, lineWidth: 1))
            .foregroundStyle(ticked ? theme.accent.color : theme.mutedText.color)
        }
        .buttonStyle(.plain)
        .help(ticked ? "\(card.name) will take commands" : "\(card.name) is not listening")
    }

    private var dropHint: some View {
        HStack(spacing: appearance.settings.panelSpacing) {
            Image(systemName: "arrow.down.doc")
            Text("Drop instruction files — they run in this order")
            Spacer(minLength: 0)
        }
        .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
        .foregroundStyle(theme.accent.color)
        .padding(.horizontal, appearance.settings.panelPadding)
        .frame(height: appearance.settings.fontSize * 2.4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accentFill.color, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.accent.color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        .allowsHitTesting(false)
    }

    /// The instruction files waiting to go, in the order they merge.
    private var fileRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: appearance.settings.panelSpacing) {
                ForEach(model.droppedFiles) { file in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text(file.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button { model.detach(file.id) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .help("Don't send this one")
                    }
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.chipFill.color, in: Capsule())
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
    }

    private var messageBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            messageField
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.chipFill.color))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.hairline.color, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) { sendGlyph }
    }

    private var messageField: some View {
        ScrollView(.vertical) {
            TextField("", text: $draft, prompt: Text("สั่งงานทุกตัวที่เลือก…"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: appearance.settings.fontSize))
                // Return sends, Shift/Option-Return breaks the line — the same
                // contract as the chat box, for the same `onSubmit` reason.
                .onKeyPress(.return, phases: .down) { press in
                    let newlineKeys: EventModifiers = [.shift, .option]
                    guard press.modifiers.isDisjoint(with: newlineKeys) else {
                        breakLineAtCaret()
                        return .handled
                    }
                    send()
                    return .handled
                }
                .focused($boxFocused)
                .padding(.trailing, sendGlyphLane)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: MessageBoxHeightKey.self, value: proxy.size.height)
                    }
                )
                // Below the measurement, so the box's own height keeps coming
                // from the text: in a stretched box the caret belongs at the
                // top, not floating at the bottom of the granted space.
                .frame(
                    minHeight: max(0, boxHeight + model.extraBoxHeight - 8),
                    alignment: .topLeading
                )
        }
        .onPreferenceChange(MessageBoxHeightKey.self) { draftHeight = $0 }
        // The granted extra rides on top of the draft-driven height, so a
        // taller window is a taller writing area and nothing else moves.
        .frame(height: boxHeight + model.extraBoxHeight)
        .scrollDisabled(draftHeight <= maxBoxHeight + model.extraBoxHeight)
        .defaultScrollAnchor(.bottom)
    }

    private var footer: some View {
        HStack {
            Button("จบการทำงาน") { model.endAll() }
                .buttonStyle(.bordered)
                .font(.system(size: appearance.settings.footnoteFontSize))
                .foregroundStyle(model.commanded.isEmpty ? theme.mutedText.color : theme.danger.color)
                .disabled(model.commanded.isEmpty)
                .help("End every session this window has commanded")
            Spacer()
            Text("Esc ซ่อนหน้าต่าง — session ยังทำงานต่อ")
                .font(.system(size: appearance.settings.hintFontSize))
                .foregroundStyle(theme.mutedText.color)
        }
    }

    private var sendGlyphSize: Double { appearance.settings.fontSize * 1.1 * 0.9 }
    private var sendGlyphLane: Double { sendGlyphSize + 16 }

    private var sendGlyph: some View {
        Button(action: send) {
            Image(systemName: "return")
                .font(.system(size: sendGlyphSize, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            canSend ? AnyShapeStyle(theme.primaryText.color)
                    : AnyShapeStyle(theme.mutedText.color)
        )
        .disabled(!canSend)
        .help("Return to send")
        .padding(.trailing, 8)
        .padding(.bottom, 5)
    }

    /// Hands the drag to the native loop the moment it starts. `performDrag`
    /// blocks until the mouse goes up, so this fires effectively once.
    private var windowDrag: some Gesture {
        DragGesture(minimumDistance: 2).onChanged { _ in beginWindowDrag() }
    }

    /// The width affordance. Only a glyph: the resizing itself is the
    /// window's own edge-resize — the panel is `.resizable` with the height
    /// pinned to the content, so grabbing any edge changes width alone. A
    /// gesture of our own here fought the background drag (both fired at
    /// once, driven 2026-08-19) and lost to the native loop on smoothness.
    private var resizeGrip: some View {
        Image(systemName: "arrow.left.and.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(theme.mutedText.color)
            .padding(8)
            .allowsHitTesting(false)
    }

    /// The ✕. Hiding, not closing: the hint beside จบการทำงาน says so, and
    /// Esc does the same thing.
    private var closeButton: some View {
        Button(action: hideWindow) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: appearance.settings.footnoteFontSize * 1.2))
                .foregroundStyle(theme.mutedText.color)
        }
        .buttonStyle(.plain)
        .help("Hide — sessions keep running")
    }

    /// A dropped file on its own is a command, same as an attachment in chat.
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty || !model.droppedFiles.isEmpty
    }

    private func send() {
        guard canSend else { return }
        if model.send(draft) { draft = "" }
    }

    /// Shift/Option-Return breaks the line where the caret is, through the
    /// field editor — the append-at-the-end version already shipped as a bug
    /// in the chat box (2026-08-17), and this box must not re-ship it.
    private func breakLineAtCaret() {
        guard let editor = NSApp.windows
            .compactMap({ $0.firstResponder as? NSTextView })
            .first(where: \.isEditable)
        else {
            draft.append("\n")
            return
        }
        editor.insertNewlineIgnoringFieldEditor(nil)
    }

    private var lineHeight: Double {
        Double(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: appearance.settings.fontSize)))
    }

    private var maxBoxHeight: Double { lineHeight * Double(ChatPanelView.inputLineLimit) }

    private var boxHeight: Double {
        SecretaryCore.messageBoxHeight(
            draft: draftHeight,
            lineHeight: lineHeight,
            lineLimit: ChatPanelView.inputLineLimit
        )
    }
}

/// Carries the slab's rendered height out to the window that has to match it.
struct SlabHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}
