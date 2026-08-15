import AppKit
import SwiftUI
import SecretaryCore

/// The composer: the growing message box, the attachments riding with it, the
/// file-request card and the ↵ that sends.
extension ChatPanelView {
    /// Asked for: the message box grows to five lines and then scrolls. Past
    /// five it starts eating the conversation it's replying to.
    static let inputLineLimit = 5

    /// The box spans the full width, with the send affordance inside it rather
    /// than a button beside it.
    var inputRow: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            if let asking = secretary.fileRequestDescription { fileRequestCard(asking) }
            messageBox
        }
        // The drop target is the whole composer, not the text field alone: the
        // chips and the button below are part of "put it here", and a file let
        // go two points outside a text field is a file the person believes they
        // handed over.
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { secretary.attach(url) }
            return !urls.isEmpty
        } isTargeted: { droppingFile = $0 }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.accent.color, lineWidth: droppingFile ? 2 : 0)
                .allowsHitTesting(false)
        )
    }

    /// The chips live *in* the field rather than above it because that is what
    /// they are — part of the message being written, not a separate thing that
    /// happens to be nearby. Sending takes both, and the box that Return
    /// belongs to should look like it holds both.
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

    /// The field is left to grow to its full height and a `ScrollView` is what's
    /// capped, rather than capping the field with `lineLimit`. Both look the same
    /// until you reach for the wheel: a line-limited field scrolls only to follow
    /// the caret, and a wheel over it does nothing at all.
    private var messageField: some View {
        ScrollView(.vertical) {
            // The persona's own name, not "the Secretary": the app can be
            // several people and the box should ask for whoever is listening.
            TextField("", text: $draft, prompt: Text("Ask \(secretary.profile.displayName)…"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: appearance.settings.fontSize))
                // Return sends. `onSubmit` doesn't fire for a vertical field in
                // this panel — Return quietly drops first responder instead —
                // which would leave no way to send from the keyboard.
                // Shift/Option-Return is left alone so it still breaks the line.
                .onKeyPress(.return, phases: .down) { press in
                    let newlineKeys: EventModifiers = [.shift, .option]
                    guard press.modifiers.isDisjoint(with: newlineKeys) else {
                        // Inserted here rather than passed on. Handing Shift+Return
                        // back to the field left it doing nothing at all — the
                        // modifier is swallowed and the line never breaks — which
                        // is why only Option+Return worked.
                        draft.append("\n")
                        return .handled
                    }
                    send()
                    return .handled
                }
                .focused($messageBoxFocused)
                // The lane the ↵ sits in. Taken out of the field's own width so
                // the text wraps before it rather than running underneath —
                // an overlay alone would have let a long line slide behind it.
                .padding(.trailing, sendGlyphLane)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: MessageBoxHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .onPreferenceChange(MessageBoxHeightKey.self) { draftHeight = $0 }
        .frame(height: messageBoxHeight)
        // Nothing to scroll until it has outgrown the box; without this the
        // content drifts under a trackpad's rubber-banding while still short.
        .scrollDisabled(draftHeight <= maxMessageBoxHeight)
        // Keeps the newest line in view as the message grows, which is where the
        // caret is while typing.
        .defaultScrollAnchor(.bottom)
    }

    /// One line of the message font, measured rather than guessed — a fraction
    /// of the point size is wrong by a whole line at the larger text sizes.
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

    /// The files waiting to go with the next message, each with a way off the
    /// list. Attached and invisible is the state that gets a file sent twice.
    private var attachmentRow: some View {
        // Scrolls sideways rather than widening the box. Five files with long
        // names are wider than any chat panel, and a row that can push the box
        // out is a row that decides the window's width — the same mistake the
        // panels were structurally stopped from making.
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

    /// Says what kind of thing was attached at a glance, which is the one
    /// question a row of names can't answer.
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

    /// The assistant asking for a file.
    ///
    /// A card rather than a line of buttons, and its own colour: this is a
    /// question waiting on the person, which is what the approval card is too —
    /// but nothing here acts on their behalf, so it must not wear the colour
    /// that means "something is about to happen as you". Teal against the
    /// orange and red of the cards that do.
    ///
    /// A button, not a path: nobody knows where their spreadsheet is in a path,
    /// and the panel is also the only way a sandboxed build could ever open one.
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

    /// The ↵'s point size, relative to the message text. Was 1.1 — 10% smaller
    /// now that it is drawn at full strength and no longer needs the size to be
    /// noticed.
    private var sendGlyphSize: Double { appearance.settings.fontSize * 1.1 * 0.9 }

    /// How much room the ↵ needs, glyph plus breathing space on either side.
    /// Derived from the glyph's own size rather than repeating the arithmetic:
    /// a lane that stopped matching the glyph would let a long line slide back
    /// under it.
    private var sendGlyphLane: Double { sendGlyphSize + 16 }

    /// Return, drawn rather than boxed: the keyboard is how this is sent, so the
    /// affordance says which key rather than offering a second, different thing
    /// to press. Still clickable for anyone who reaches for the mouse.
    ///
    /// Bottom-aligned, because the box grows downward as the message wraps and a
    /// centred glyph would drift away from the caret.
    private var sendGlyph: some View {
        Button(action: send) {
            Image(systemName: "return")
                .font(.system(size: sendGlyphSize, weight: .medium))
        }
        .buttonStyle(.plain)
        // Empty box: exactly the placeholder's colour, so the glyph sits at the
        // same weight as the "Ask the Secretary…" beside it. It used to be
        // dimmed to 35% of that and read as switched off.
        // `placeholderTextColor` and `secondaryLabelColor` are the same value
        // (black/white at 0.5 alpha) — naming the placeholder one says which
        // of the two this is matched to.
        .foregroundStyle(
            canSend ? AnyShapeStyle(theme.primaryText.color)
                    : AnyShapeStyle(theme.mutedText.color)
        )
        .disabled(!canSend)
        .help("Return to send")
        .padding(.trailing, 8)
        .padding(.bottom, 5)
    }

    /// A file on its own is a message. Dragging a spreadsheet in and pressing
    /// Return should send it, not sit there waiting for a word to be typed.
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty || !secretary.attachments.isEmpty
    }
}

/// Carries the typed message's rendered height out of the field so the box can
/// be sized from it.
struct MessageBoxHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}
