import AppKit
import SwiftUI
import SecretaryCore

extension ChatPanelView {
    static let inputLineLimit = 10

    var inputRow: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            if let asking = secretary.fileRequestDescription { fileRequestCard(asking) }
            if !secretary.savableFiles.isEmpty { savableFilesCard(secretary.savableFiles) }
            if droppingFile { dropArea }
            messageBox
        }
        .animation(.easeOut(duration: 0.12), value: droppingFile)
    }

    private var dropArea: some View {
        HStack(spacing: appearance.settings.panelSpacing) {
            Image(systemName: "arrow.down.doc")
            Text(attachmentDropPrompt(attached: secretary.attachments.count))
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
                .strokeBorder(
                    theme.accent.color,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
        )
        .allowsHitTesting(false)
    }

    private var messageBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !secretary.attachments.isEmpty { attachmentRow }
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
            TextField("", text: $draft, prompt: Text("Ask \(secretary.profile.displayName)…"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: appearance.settings.fontSize))
                .onKeyPress(.return, phases: .down) { press in
                    let newlineKeys: EventModifiers = [.shift, .option]
                    guard press.modifiers.isDisjoint(with: newlineKeys) else {
                        breakLineAtCaret()
                        return .handled
                    }
                    send()
                    return .handled
                }
                .focused($messageBoxFocused)
                .padding(.trailing, sendGlyphLane)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: MessageBoxHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .onPreferenceChange(MessageBoxHeightKey.self) { draftHeight = $0 }
        .frame(height: messageBoxHeight)
        .scrollDisabled(draftHeight <= maxMessageBoxHeight)
        .defaultScrollAnchor(.bottom)
    }

    private func breakLineAtCaret() {
        guard let editor = editingTextView else {
            draft.append("\n")
            return
        }
        editor.insertNewlineIgnoringFieldEditor(nil)
    }

    private var editingTextView: NSTextView? {
        NSApp.windows
            .compactMap { $0.firstResponder as? NSTextView }
            .first { $0.isEditable }
    }

    private var messageLineHeight: Double {
        Double(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: appearance.settings.fontSize)))
    }

    private var maxMessageBoxHeight: Double { messageLineHeight * Double(Self.inputLineLimit) }

    private var messageBoxHeight: Double {
        SecretaryCore.messageBoxHeight(
            draft: draftHeight,
            lineHeight: messageLineHeight,
            lineLimit: Self.inputLineLimit
        )
    }

    private var attachmentRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: appearance.settings.panelSpacing) {
            ForEach(secretary.attachments) { attachment in
                HStack(spacing: 4) {
                    Image(systemName: attachmentGlyph(attachment.kind))
                    Text(attachment.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        secretary.detach(attachment.id)
                    } label: {
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

    private func attachmentGlyph(_ kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .sourceCode: return "chevron.left.forwardslash.chevron.right"
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        case .markdown, .text: return "doc.text"
        }
    }

    private func fileRequestCard(_ asking: String) -> some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            Label("Send me a file?", systemImage: "paperclip")
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
            Text(asking)
                .font(.system(size: appearance.settings.footnoteFontSize))
                .fixedSize(horizontal: false, vertical: true)
            Text("Markdown, CSV, JSON, a PDF, source code, notes or an image — or drag one onto the box below.")
                .font(.system(size: appearance.settings.hintFontSize))
                .foregroundStyle(theme.mutedText.color)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: appearance.settings.panelSpacing * 1.3) {
                Button("Choose…") {
                    for url in AttachmentPicker.promptForFiles(message: asking) {
                        secretary.attach(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Not now") { secretary.dismissFileRequest() }
                    .buttonStyle(.bordered)
            }
            .font(.system(size: appearance.settings.footnoteFontSize))
        }
        .padding(appearance.settings.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.infoFill.color, in: RoundedRectangle(cornerRadius: 8))
    }

    private func savableFilesCard(_ files: [OfferedFile]) -> some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            Label(
                files.count == 1 ? "Made you a file" : "Made you \(files.count) files",
                systemImage: "square.and.arrow.down"
            )
            .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
            ForEach(files) { file in
                HStack(spacing: appearance.settings.panelSpacing) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name)
                            .font(.system(size: appearance.settings.footnoteFontSize))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(fileSize(file.byteCount))
                            .font(.system(size: appearance.settings.hintFontSize))
                            .foregroundStyle(theme.mutedText.color)
                    }
                    Spacer(minLength: appearance.settings.panelSpacing)
                    Button("Save…") { SavePanel.save(file) }
                        .buttonStyle(.borderedProminent)
                        .font(.system(size: appearance.settings.footnoteFontSize))
                }
            }
            Button("Not now") { secretary.dismissSavableFiles() }
                .buttonStyle(.bordered)
                .font(.system(size: appearance.settings.footnoteFontSize))
        }
        .padding(appearance.settings.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.infoFill.color, in: RoundedRectangle(cornerRadius: 8))
    }

    private func fileSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty || !secretary.attachments.isEmpty
    }
}

struct MessageBoxHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}
