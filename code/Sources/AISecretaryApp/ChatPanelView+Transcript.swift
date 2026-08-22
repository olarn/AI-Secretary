import AppKit
import SwiftUI
import LLMProvider
import SecretaryCore

extension ChatPanelView {
    var emptyTranscriptHint: String {
        SecretaryCore.emptyTranscriptHint(
            backendStatus.readiness,
            makers: AIVendor.known.map(\.displayName)
        )
    }

    var transcript: some View {
        GeometryReader { viewport in
            transcriptScroller(bottomEdge: viewport.frame(in: .global).maxY)
        }
        .frame(maxHeight: .infinity)
        .onHover { pointerOverTranscript = $0 }
    }

    private func transcriptScroller(bottomEdge: Double) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if secretary.transcript.isEmpty {
                        Text(emptyTranscriptHint)
                            .font(.system(size: appearance.settings.fontSize))
                            .foregroundStyle(theme.mutedText.color)
                    }
                    TranscriptRows(
                        entries: secretary.transcript,
                        look: TranscriptLook(
                            fontSize: appearance.settings.fontSize,
                            secondaryFontSize: appearance.settings.secondaryFontSize,
                            font: appearance.settings.font,
                            width: appearance.settings.chatWidth,
                            theme: appearance.settings.theme,
                            liquidGlass: appearance.settings.liquidGlass,
                            systemIsDark: appearance.systemIsDark
                        )
                    ) { entry in
                        messageBubble(entry).id(entry.id)
                    }
                    .equatable()
                    Color.clear
                        .frame(height: appearance.settings.fontSize)
                        .id(Self.endOfTranscript)
                        .background(
                            GeometryReader { tail in
                                Color.clear.preference(
                                    key: TranscriptTailKey.self,
                                    value: tail.frame(in: .global).maxY
                                )
                            }
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onPreferenceChange(TranscriptTailKey.self) { endOfContent in
                let distance = endOfContent - bottomEdge
                var pin = scrollPin
                pin.update(distanceBelowFold: distance)
                if pin != scrollPin { scrollPin = pin }
                guard pin.isBehind(distanceBelowFold: distance) else { return }
                proxy.scrollTo(Self.endOfTranscript, anchor: .bottom)
            }
            .onChange(of: secretary.transcript.count) { before, after in
                guard after < before else { return }
                partsCache.keepingOnly(Set(secretary.transcript.map(\.id)))
            }
        }
    }

    private static let endOfTranscript = "end-of-transcript"

    @ViewBuilder
    private func messageBubble(_ entry: TranscriptEntry) -> some View {
        let style = messageBubbleStyle(speaker: entry.speaker, kind: entry.kind)
        if !style.isBubble {
            activityRow(entry)
        } else {
            let parts = partsCache.parts(id: entry.id, text: entry.text)
            VStack(alignment: style.side == .trailing ? .trailing : .leading, spacing: 9) {
                if style.showsSpeakerName {
                    messageRow(style: style) {
                        header(entry, style: style).padding(.horizontal, 2)
                    }
                }
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    messageRow(style: style) {
                        partView(part, entry: entry, style: style, index: index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func partView(
        _ part: MessagePart,
        entry: TranscriptEntry,
        style: MessageBubbleStyle,
        index: Int
    ) -> some View {
        let box = BoxID(entry: entry.id, index: index)
        Group {
            switch part {
            case .prose(let segments):
                proseBubble(segments, style: style)
            case .block(let segment):
                blockView(segment)
            }
        }
        .overlay(alignment: .topTrailing) {
            if style.showsCopyButton {
                WhenPointingAt(box: box, hover: hover) {
                    boxButtons(text: copyText(of: part), box: box, entry: entry)
                        .offset(x: 10, y: -10)
                }
            }
        }
        .onHover { hover.report(pointerIsInside: $0, over: box) }
    }

    struct BoxID: Equatable {
        let entry: UUID
        let index: Int
    }

    private func messageRow<Content: View>(
        style: MessageBubbleStyle,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            if style.side == .trailing {
                Spacer(minLength: messageBubbleGutter(panelWidth: appearance.settings.chatWidth))
            }
            content()
            if style.side == .leading {
                Spacer(minLength: messageBubbleGutter(panelWidth: appearance.settings.chatWidth))
            }
        }
    }

    @ViewBuilder
    private func blockView(_ segment: TranscriptSegment) -> some View {
        switch segment {
        case .table(let table): tableView(table)
        case .code(let block): codeView(block)
        case .text(let body): Text(body)
        }
    }

    private func header(_ entry: TranscriptEntry, style: MessageBubbleStyle) -> some View {
        HStack(spacing: 5) {
            if style.isFailure {
                Label("Couldn't reply", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: appearance.settings.secondaryFontSize, weight: .bold))
            } else {
                Text(speakerLabel(isMine: style.isMine, speakerName: entry.speakerName))
                    .font(.system(size: appearance.settings.secondaryFontSize, weight: .bold))
            }
            Text(MessageTime.label(for: entry.timestamp))
                .font(.system(size: appearance.settings.secondaryFontSize))
        }
        .foregroundStyle(style.isFailure ? theme.warning.color : theme.mutedText.color)
    }

    private func boxButtons(text: String, box: BoxID, entry: TranscriptEntry) -> some View {
        HStack(spacing: 2) {
            pinButton(text: text, entry: entry)
            copyButton(text: text, box: box)
        }
    }

    private func pinButton(text: String, entry: TranscriptEntry) -> some View {
        Button {
            onPin(
                InfoWindowSpec(
                    title: "\(speakerLabel(isMine: false, speakerName: entry.speakerName)) · \(MessageTime.label(for: entry.timestamp))",
                    body: text
                )
            )
        } label: {
            Image(systemName: "pin")
                .font(.system(size: appearance.settings.secondaryFontSize))
                .foregroundStyle(theme.mutedText.color)
                .padding(4)
                .background(theme.chipFill.color, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Pin this box into its own window")
    }

    private func copyButton(text: String, box: BoxID) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            confirmCopy(of: box)
        } label: {
            Image(systemName: hover.copied == box ? "checkmark" : "doc.on.doc")
                .font(.system(size: appearance.settings.secondaryFontSize))
                .foregroundStyle(theme.mutedText.color)
                .padding(4)
                .background(theme.chipFill.color, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Copy this box")
    }

    private func confirmCopy(of box: BoxID) {
        hover.copied = box
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if hover.copied == box { hover.copied = nil }
        }
    }

    private func proseBubble(
        _ segments: [TranscriptSegment],
        style: MessageBubbleStyle
    ) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if case .text(let body) = segment {
                        MessageTextView(
                            text: MessageMarkdown.attributed(body),
                            fontSize: appearance.settings.fontSize,
                            font: appearance.settings.font,
                            palette: theme
                        )
                        .frame(
                            maxWidth: MessageTextView.naturalWidth(
                                MessageMarkdown.attributed(body),
                                fontSize: appearance.settings.fontSize,
                                font: appearance.settings.font
                            ),
                            alignment: .leading
                        )
                    }
                }
            }
            .padding(.horizontal, Self.bubbleTextInset)
            .padding(.vertical, 10)
            .background(bubbleFill(style), in: RoundedRectangle(cornerRadius: 12))
    }

    private static let bubbleTextInset: Double = 14

    private func bubbleFill(_ style: MessageBubbleStyle) -> Color {
        if style.isFailure { return theme.warningFill.color }
        return (style.isMine ? theme.bubbleMine : theme.bubbleTheirs).color
    }

    private func codeView(_ block: CodeBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = block.language {
                Text(language)
                    .font(.system(size: appearance.settings.secondaryFontSize))
                    .foregroundStyle(theme.mutedText.color)
                    .padding(.horizontal, 8)
                    .padding(.top, 5)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(block.code)
                    .font(.system(size: appearance.settings.fontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.nestedFill.color, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.hairline.color, lineWidth: 1)
        )
    }

    private func tableView(_ table: MarkdownTable) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { _, cell in
                        Text(inlineMarkdown(cell))
                            .font(.system(
                                size: appearance.settings.fontSize,
                                weight: .bold,
                                design: appearance.settings.font.swiftUIDesign
                            ))
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inlineMarkdown(cell))
                                .font(.system(
                                    size: appearance.settings.fontSize,
                                    design: appearance.settings.font.swiftUIDesign
                                ))
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(8)
            .textSelection(.enabled)
        }
        .background(theme.nestedFill.color, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.hairline.color, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        MessageMarkdown.attributed(text)
    }

    private func activityRow(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if messageBubbleStyle(speaker: entry.speaker, kind: entry.kind).showsWorkingLabel {
                Label("Working", systemImage: "gearshape.2")
                    .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
            }
            Text(entry.text)
                .font(.system(size: appearance.settings.secondaryFontSize, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.mutedText.color)
        .padding(.leading, Self.bubbleTextInset)
        .padding(.trailing, messageBubbleGutter(panelWidth: appearance.settings.chatWidth))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TranscriptLook: Equatable {
    let fontSize: Double
    let secondaryFontSize: Double
    let font: FontChoice
    let width: Double
    let theme: ThemeChoice
    let liquidGlass: Bool
    let systemIsDark: Bool
}

private struct TranscriptRows<Row: View>: View, Equatable {
    let entries: [TranscriptEntry]
    let look: TranscriptLook
    @ViewBuilder let row: (TranscriptEntry) -> Row

    static func == (lhs: TranscriptRows, rhs: TranscriptRows) -> Bool {
        lhs.entries == rhs.entries && lhs.look == rhs.look
    }

    var body: some View {
        ForEach(entries) { entry in row(entry) }
    }
}
