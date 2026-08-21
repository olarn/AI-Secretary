import SwiftUI
import Permissions
import SecretaryCore

/// The command window: tick who should listen, type once, everyone ticked
/// gets it. Spotlight-shaped — one borderless rounded slab — with the
/// character list above the box, the same growing message box the chat uses,
/// the red line under it when nothing can go, and a foldable strip of what
/// the commanded characters have answered.
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

    @State private var draftHeight: Double = 0
    @State private var resultsHeight: Double = 0
    @State private var droppingFile = false
    /// Whether Copy has just run, so the glyph can say so.
    @State private var copied = false
    @State private var approvalsHeight: Double = 0
    @FocusState private var boxFocused: Bool

    private var theme: Palette { appearance.colors }
    /// Every size on the slab, from *this box's* text size rather than the
    /// chat's. They came off `appearance.settings` before, so ⌘+ grew the words
    /// being typed and left the chips, the results and the rhythm where they
    /// were — the owner's report opening Sprint 21.2.
    private var metrics: TextMetrics { TextMetrics(fontSize: model.fontSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.panelSpacing) {
            characterRow
            if droppingFile { dropHint }
            if !model.droppedFiles.isEmpty || !model.pendingAttachments.isEmpty { fileRow }
            messageBox
            if let error = model.errorText {
                Text(error)
                    .font(.system(size: metrics.footnoteFontSize))
                    .foregroundStyle(theme.danger.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.approvals.isEmpty { approvalsSection }
            if !model.results.isEmpty { resultsSection }
            footer
        }
        .padding(metrics.panelPadding * 1.5)
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
        HStack(spacing: metrics.panelSpacing) {
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
            .font(.system(size: metrics.footnoteFontSize, weight: ticked ? .semibold : .regular))
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
        HStack(spacing: metrics.panelSpacing) {
            Image(systemName: "arrow.down.doc")
            Text("Drop instruction files — they run in this order")
            Spacer(minLength: 0)
        }
        .font(.system(size: metrics.footnoteFontSize, weight: .semibold))
        .foregroundStyle(theme.accent.color)
        .padding(.horizontal, metrics.panelPadding)
        .frame(height: model.fontSize * 2.4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accentFill.color, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.accent.color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        .allowsHitTesting(false)
    }

    /// Everything waiting to go with the next send: instruction files in
    /// merge order, then the attachments.
    private var fileRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: metrics.panelSpacing) {
                ForEach(model.droppedFiles) { file in
                    fileChip(name: file.name, glyph: "doc.text", id: file.id)
                }
                ForEach(model.pendingAttachments) { file in
                    fileChip(name: file.name, glyph: "paperclip", id: file.id)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
    }

    private func fileChip(name: String, glyph: String, id: UUID) -> some View {
        HStack(spacing: 4) {
            Image(systemName: glyph)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Button { model.detach(id) } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Don't send this one")
        }
        .font(.system(size: metrics.footnoteFontSize))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(theme.chipFill.color, in: Capsule())
    }

    private var messageBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            messageField
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.chipFill.color))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.hairline.color, lineWidth: 1))
        // The controls live *in* the box since 20.1 — the owner asked for
        // Clear at its bottom-left corner drawn like the send affordance, and
        // the paperclip beside ↵ rather than out in the footer.
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 12) {
                paperclipGlyph
                sendGlyph
            }
        }
        .overlay(alignment: .bottomLeading) { clearGlyph }
    }

    private var messageField: some View {
        ScrollView(.vertical) {
            TextField("", text: $model.draft, prompt: Text("Command everyone ticked…"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: model.fontSize))
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
                // The control row's strip: text scrolls above Clear/📎/↵
                // instead of running underneath them.
                .padding(.bottom, sendGlyphSize + 12)
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
        // The field is top-aligned and only as tall as its text, so in a
        // stretched box most of the writing area is empty scroll space — a
        // click there must still land the caret, or the box reads as dead
        // (driven 2026-08-19: a click mid-box typed nowhere).
        .contentShape(Rectangle())
        .onTapGesture { boxFocused = true }
        .scrollDisabled(draftHeight <= maxBoxHeight + model.extraBoxHeight)
        .defaultScrollAnchor(.bottom)
    }

    // MARK: - Permission cards

    /// What a commanded character is blocked on, asked here.
    ///
    /// Never foldable, unlike the results: this is the one thing on the slab
    /// that is waiting on the person, and a question tucked behind a chevron is
    /// the bug this was written to fix.
    private var approvalsSection: some View {
        // Capped and scrolling inside itself, exactly like the results strip
        // and for a stronger reason. Four characters commanded at once raise
        // four cards, and uncapped they grew the window to 921pt on a 1030pt
        // screen — driven 2026-08-21 — which pushed the later cards and the
        // whole results strip off the bottom of the display. **A card nobody
        // can reach is the bug this section was written to fix**, so it must
        // not be able to come back by the window simply getting too tall.
        //
        // Measured-then-capped rather than a bare `maxHeight`: a `ScrollView`
        // with an unbounded max collapses to nothing, which is how the results
        // strip once showed its header and not one row.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: metrics.panelSpacing) {
                ForEach(model.approvals) { approval in
                    approvalRow(approval)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ApprovalsHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .onPreferenceChange(ApprovalsHeightKey.self) { approvalsHeight = $0 }
        // Room for two cards at a comfortable size; the rest scroll. Questions
        // outrank answers, so this is given more of the slab than the results.
        .frame(height: min(320, approvalsHeight))
        .padding(metrics.panelSpacing)
        .background(theme.warningFill.color, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.warning.color, lineWidth: 1)
        )
    }

    private func approvalRow(_ approval: CommandApproval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "lock")
                    .font(.system(size: metrics.footnoteFontSize))
                Text("\(approval.name) needs your permission")
                    .font(.system(size: metrics.footnoteFontSize, weight: .semibold))
            }
            Text(approval.question)
                .font(.system(size: metrics.footnoteFontSize))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            // The card's own answers, so the buttons here and the buttons in
            // her chat can never come apart — `offeredApprovalAnswers` decides
            // whether Always is on offer at all.
            HStack(spacing: 6) {
                ForEach(approval.answers, id: \.self) { permission in
                    Button(permission.title) {
                        model.answer(permission, to: approval)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: metrics.footnoteFontSize, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        permission == .deny ? theme.chipFill.color : theme.accentFill.color,
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(
                            permission == .deny ? theme.hairline.color : theme.accent.color,
                            lineWidth: 1
                        )
                    )
                    .foregroundStyle(
                        permission == .deny ? theme.mutedText.color : theme.accent.color
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Results

    /// What has come back, foldable like the usage window's sections — the
    /// whole header row is the target, not a 10pt chevron.
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: metrics.panelSpacing) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { model.showResults.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: max(8, metrics.footnoteFontSize - 3), weight: .bold))
                            .foregroundStyle(theme.mutedText.color)
                            .rotationEffect(.degrees(model.showResults ? 90 : 0))
                        Text("Results")
                            .font(.system(size: metrics.footnoteFontSize, weight: .semibold))
                        Text("\(model.results.count)")
                            .font(.system(size: metrics.hintFontSize))
                            .foregroundStyle(theme.mutedText.color)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if model.showResults {
                    // copy, Save, clear — the owner's order (2026-08-20).
                    copyResultsButton
                    saveResultsButton
                    Button("clear") { model.clearResults() }
                        .buttonStyle(.plain)
                        .font(.system(size: metrics.hintFontSize))
                        .foregroundStyle(theme.mutedText.color)
                        .help("Empty the results strip — sessions are untouched")
                }
            }

            if model.showResults {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: metrics.panelSpacing) {
                        ForEach(model.results) { result in
                            resultRow(result)
                        }
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ResultsHeightKey.self, value: proxy.size.height)
                        }
                    )
                }
                .onPreferenceChange(ResultsHeightKey.self) { resultsHeight = $0 }
                // Sized from the measured rows, capped: a bare `maxHeight`
                // lets a ScrollView collapse to nothing — driven 2026-08-19,
                // where the strip showed its header and not one row. A strip,
                // not a transcript: a few answers, its own scroll for the
                // rest, so results can never crowd out the box.
                .frame(height: min(220, resultsHeight))
            }
        }
        .padding(metrics.panelSpacing)
        .background(theme.infoFill.color(opacity: 0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Writes the strip to a file the person names. Markdown by default —
    /// the answers are Markdown, and the owner named the extension.
    private var saveResultsButton: some View {
        Button("Save") {
            SavePanel.saveText(model.resultsMarkdown, named: commandResultsFileName)
        }
        .buttonStyle(.plain)
        .font(.system(size: metrics.hintFontSize))
        .foregroundStyle(theme.mutedText.color)
        .help("Save the results to a file")
    }

    /// The same document, on the clipboard. The glyph turns into a tick for a
    /// moment: a copy that changes nothing on screen is indistinguishable from
    /// a button that did nothing.
    private var copyResultsButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.resultsMarkdown, forType: .string)
            copied = true
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: metrics.hintFontSize))
        }
        .buttonStyle(.plain)
        .foregroundStyle(copied ? theme.success.color : theme.mutedText.color)
        .help("Copy the results to the clipboard")
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }

    private func resultRow(_ result: CommandResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(result.succeeded ? theme.success.color : theme.danger.color)
                    .frame(width: 6, height: 6)
                Text(result.name)
                    .font(.system(size: metrics.footnoteFontSize, weight: .semibold))
                // Same words the chat puts beside a name, so the two windows
                // never disagree about what time something happened.
                Text(MessageTime.label(for: result.receivedAt))
                    .font(.system(size: metrics.hintFontSize))
                    .foregroundStyle(theme.mutedText.color)
            }
            Text(result.text)
                .font(.system(size: metrics.footnoteFontSize))
                .lineLimit(8)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !result.choices.isEmpty {
                // The reply asked something. Answering sends the option's own
                // words to that character — the chat picker's rule, because a
                // bare letter is ambiguous for the next turn.
                WrappingChoices(
                    options: result.choices,
                    fontSize: metrics.footnoteFontSize,
                    theme: theme
                ) { option in
                    model.pick(option, from: result)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: metrics.panelSpacing * 1.5) {
            Button("End all") { model.endAll() }
                .buttonStyle(.bordered)
                .font(.system(size: metrics.footnoteFontSize))
                .foregroundStyle(model.commanded.isEmpty ? theme.mutedText.color : theme.danger.color)
                .disabled(model.commanded.isEmpty)
                .help("End every session this window has commanded")
            Spacer()
            Text("Esc hides the window — sessions keep running")
                .font(.system(size: metrics.hintFontSize))
                .foregroundStyle(theme.mutedText.color)
        }
    }

    private var sendGlyphSize: Double { model.fontSize * 1.1 * 0.9 }
    /// Two glyphs share the lane now — ↵ and the paperclip beside it.
    private var sendGlyphLane: Double { sendGlyphSize * 2 + 32 }

    /// "Clear", drawn exactly like the send affordance — a word, not a border
    /// — at the box's bottom-left, per the 20.1 spec.
    private var clearGlyph: some View {
        Button("Clear") { model.clearComposition() }
            .buttonStyle(.plain)
            .font(.system(size: sendGlyphSize, weight: .medium))
            .foregroundStyle(
                canSend ? AnyShapeStyle(theme.primaryText.color)
                        : AnyShapeStyle(theme.mutedText.color)
            )
            .disabled(!canSend)
            .help("Empty the box and the waiting files — nothing is sent")
            .padding(.leading, 8)
            .padding(.bottom, 5)
    }

    private var paperclipGlyph: some View {
        Button {
            for url in AttachmentPicker.promptForFiles(message: "instruction files or attachments") {
                model.attach(url)
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: sendGlyphSize, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.mutedText.color)
        .help("Attach files without dragging")
        .padding(.bottom, 5)
    }

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

    /// The ✕. Hiding, not closing: the hint beside จบการทำงาน says so, and
    /// Esc does the same thing.
    private var closeButton: some View {
        Button(action: hideWindow) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: metrics.footnoteFontSize * 1.2))
                .foregroundStyle(theme.mutedText.color)
        }
        .buttonStyle(.plain)
        .help("Hide — sessions keep running")
    }

    /// A dropped file on its own is a command, same as an attachment in chat.
    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespaces).isEmpty
            || !model.droppedFiles.isEmpty
            || !model.pendingAttachments.isEmpty
    }

    private func send() {
        guard canSend else { return }
        _ = model.send()
    }

    /// Shift/Option-Return breaks the line where the caret is, through the
    /// field editor — the append-at-the-end version already shipped as a bug
    /// in the chat box (2026-08-17), and this box must not re-ship it.
    private func breakLineAtCaret() {
        guard let editor = NSApp.windows
            .compactMap({ $0.firstResponder as? NSTextView })
            .first(where: \.isEditable)
        else {
            model.draft.append("\n")
            return
        }
        editor.insertNewlineIgnoringFieldEditor(nil)
    }

    private var lineHeight: Double {
        Double(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: model.fontSize)))
    }

    private var maxBoxHeight: Double { lineHeight * Double(ChatPanelView.inputLineLimit) }

    /// Never shorter than 2.5 lines — the owner's number (20.1), room for the
    /// control row without the box reading as a single cramped line.
    private var boxHeight: Double {
        max(
            SecretaryCore.messageBoxHeight(
                draft: draftHeight,
                lineHeight: lineHeight,
                lineLimit: ChatPanelView.inputLineLimit
            ),
            lineHeight * 2.5 + sendGlyphSize + 12
        )
    }
}

/// Choice buttons that wrap to the strip's width instead of forcing it wider —
/// the same must-not-decide-the-window-size rule every panel here lives by.
private struct WrappingChoices: View {
    let options: [String]
    let fontSize: Double
    let theme: Palette
    let pick: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(options, id: \.self) { option in
                Button { pick(option) } label: {
                    Text(option)
                        .font(.system(size: fontSize))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(theme.accentFill.color, in: Capsule())
                        .overlay(Capsule().stroke(theme.accent.color, lineWidth: 1))
                        .foregroundStyle(theme.accent.color)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Rows of subviews, wrapping when the line is full. A `Layout` because
/// HStacks cannot wrap and a `Grid` would make every column as wide as the
/// longest option.
private struct FlowLayout: Layout {
    let spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(in: bounds.width, subviews: subviews).origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(in width: Double, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x = 0.0, y = 0.0, rowHeight = 0.0, widest = 0.0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, CGSize(width: widest, height: y + rowHeight))
    }
}

/// Carries the waiting cards' height out to the strip that has to cap it, so
/// four of them cannot push the window past the bottom of the screen.
private struct ApprovalsHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}

/// Carries the result rows' height out to the strip that has to cap it.
private struct ResultsHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}

/// Carries the slab's rendered height out to the window that has to match it.
struct SlabHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}
