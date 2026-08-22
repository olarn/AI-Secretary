import SwiftUI
import Permissions
import SecretaryCore

struct CommandWindowView: View {
    @Bindable var model: CommandCenter
    let appearance: Appearance
    let beginWindowDrag: () -> Void
    let hideWindow: () -> Void
    let contentHeightChanged: (Double) -> Void

    @State private var draftHeight: Double = 0
    @State private var resultsHeight: Double = 0
    @State private var droppingFile = false
    @State private var copied = false
    @State private var approvalsHeight: Double = 0
    @FocusState private var boxFocused: Bool

    private var theme: Palette { appearance.colors }
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
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.ground.color)
                .gesture(windowDrag)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.panelBorder.color, lineWidth: theme.panelBorderWidth))
        .overlay(alignment: .topTrailing) { closeButton.padding(6) }
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
                .padding(.bottom, sendGlyphSize + 12)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: MessageBoxHeightKey.self, value: proxy.size.height)
                    }
                )
                .frame(
                    minHeight: max(0, boxHeight + model.extraBoxHeight - 8),
                    alignment: .topLeading
                )
        }
        .onPreferenceChange(MessageBoxHeightKey.self) { draftHeight = $0 }
        .frame(height: boxHeight + model.extraBoxHeight)
        .contentShape(Rectangle())
        .onTapGesture { boxFocused = true }
        .scrollDisabled(draftHeight <= maxBoxHeight + model.extraBoxHeight)
        .defaultScrollAnchor(.bottom)
    }

    private var approvalsSection: some View {
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
                .frame(height: min(220, resultsHeight))
            }
        }
        .padding(metrics.panelSpacing)
        .background(theme.infoFill.color(opacity: 0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var saveResultsButton: some View {
        Button("Save") {
            SavePanel.saveText(model.resultsMarkdown, named: commandResultsFileName)
        }
        .buttonStyle(.plain)
        .font(.system(size: metrics.hintFontSize))
        .foregroundStyle(theme.mutedText.color)
        .help("Save the results to a file")
    }

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
    private var sendGlyphLane: Double { sendGlyphSize * 2 + 32 }

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

    private var windowDrag: some Gesture {
        DragGesture(minimumDistance: 2).onChanged { _ in beginWindowDrag() }
    }

    private var closeButton: some View {
        Button(action: hideWindow) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: metrics.footnoteFontSize * 1.2))
                .foregroundStyle(theme.mutedText.color)
        }
        .buttonStyle(.plain)
        .help("Hide — sessions keep running")
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespaces).isEmpty
            || !model.droppedFiles.isEmpty
            || !model.pendingAttachments.isEmpty
    }

    private func send() {
        guard canSend else { return }
        _ = model.send()
    }

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

private struct ApprovalsHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}

private struct ResultsHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}

struct SlabHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}
