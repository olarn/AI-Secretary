import AppKit
import SwiftUI
import LLMProvider
import SecretaryCore

/// The thread itself: the scroller and its follow-the-bottom rule, and how one
/// message becomes bubbles, tables, code blocks and activity lines.
extension ChatPanelView {
    var emptyTranscriptHint: String {
        SecretaryCore.emptyTranscriptHint(
            backendStatus.readiness,
            makers: AIVendor.known.map(\.displayName)
        )
    }

    var transcript: some View {
        // The outer reader is only here for one number: where the bottom edge
        // of the visible area is, to compare the end of the content against.
        GeometryReader { viewport in
            transcriptScroller(bottomEdge: viewport.frame(in: .global).maxY)
        }
        .frame(maxHeight: .infinity)
        .onHover { pointerOverTranscript = $0 }
    }

    private func transcriptScroller(bottomEdge: Double) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Eager, and it has to stay eager. `LazyVStack` was tried here
                // — it would let the strip at the end report its own visibility
                // and it builds far less per token — and it puts the scroll bar
                // in the wrong place: parked at the very bottom of a reply, the
                // thumb sat half way down its track, because the height of a
                // list whose rows haven't been built is a guess.
                //
                // Spacing wider than the gap between boxes of one turn, so the
                // eye groups a split answer together before it groups the
                // conversation.
                VStack(alignment: .leading, spacing: 16) {
                    if secretary.transcript.isEmpty {
                        Text(emptyTranscriptHint)
                            .font(.system(size: appearance.settings.fontSize))
                            .foregroundStyle(theme.mutedText.color)
                    }
                    // Wrapped so a keystroke in the message box does not
                    // rebuild every message in the conversation — see
                    // `TranscriptRows`, which is where the measurement is.
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
                    // Breathing room under the last line, and the thing that
                    // reports whether the reader is at the bottom.
                    //
                    // The room came first: scrolled to the bottom, the final
                    // line sat flush against the edge and read as cut off — and
                    // with a descender or a second line arriving mid-stream it
                    // genuinely was. Scaled to the text size, because the amount
                    // that goes missing scales with it too.
                    //
                    // Where this strip is relative to the bottom edge is the
                    // only input following has: it says both "the bottom is on
                    // screen" — which is the only thing that may switch
                    // following back on — and "the end has been pushed out of
                    // sight", which is what asks for a scroll. What it must
                    // never be read as is the reader scrolling away, since
                    // content growing under a reader who hasn't moved looks
                    // identical from here. Leaving is the scroll wheel's
                    // business alone, in `startWatchingScroll`.
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
            // How far the end of the transcript sits below the bottom edge.
            //
            // Measured in `.global` deliberately. The first version of this
            // asked for the content's frame in a *named* coordinate space on
            // the scroll view, and that preference was delivered exactly once,
            // at launch — not on a single token of a reply, not on a single
            // turn of the wheel. It read correctly and never ran; the same
            // reading in global coordinates fires throughout.
            .onPreferenceChange(TranscriptTailKey.self) { endOfContent in
                let distance = endOfContent - bottomEdge
                // Assigned only when the answer changes: writing to `@State`
                // invalidates the view whether or not the value differs, and
                // this arrives on every token.
                var pin = scrollPin
                pin.update(distanceBelowFold: distance)
                if pin != scrollPin { scrollPin = pin }
                // The one place following is decided, and it is decided from
                // where the end of the content actually is rather than from a
                // guess about what might have moved it. Scrolling changes this
                // measurement, which arrives here again — and converges, since
                // the end sitting at the bottom edge is `settled` and asks for
                // nothing further.
                //
                // Unanimated: an animated scroll is still moving when the next
                // token arrives and asks for another one, and the two fight
                // each other into a visible judder.
                guard pin.isBehind(distanceBelowFold: distance) else { return }
                proxy.scrollTo(Self.endOfTranscript, anchor: .bottom)
            }
            // A conversation only ever gets shorter by being replaced — started
            // again, or an older one loaded — and that is the moment the parses
            // of messages that are no longer on screen stop being worth
            // keeping. Pruning here rather than per message keeps the walk off
            // the token-by-token path.
            .onChange(of: secretary.transcript.count) { before, after in
                guard after < before else { return }
                partsCache.keepingOnly(Set(secretary.transcript.map(\.id)))
            }
        }
    }

    /// The strip below the last message: what following scrolls to, and what
    /// being at the bottom is measured against.
    ///
    /// Scrolled to, rather than to the last message: the last message's bottom
    /// is a line of text short of the end, which left the breathing room under
    /// it permanently off screen and made "am I at the bottom?" a question
    /// about a strip nobody could see.
    private static let endOfTranscript = "end-of-transcript"

    @ViewBuilder
    private func messageBubble(_ entry: TranscriptEntry) -> some View {
        let style = messageBubbleStyle(speaker: entry.speaker, kind: entry.kind)
        if !style.isBubble {
            activityRow(entry)
        } else {
            // Markers stripped, and pasted rows recognised as tables — someone
            // handing over data has it as CSV far more often than as pipes, and
            // a wall of commas is exactly what they can't check before it is
            // typed into a form.
            //
            // Through the cache because this runs for every message in the
            // conversation on every token of the one still arriving.
            let parts = partsCache.parts(id: entry.id, text: entry.text)
            // Boxes within one turn sit closer together than turns do, but not
            // as close as they were: three boxes 5pt apart read as one striped
            // block rather than as three things.
            VStack(alignment: style.side == .trailing ? .trailing : .leading, spacing: 9) {
                // Both speakers are named above their boxes, not inside them:
                // the name is about the turn, and a reply split into three
                // boxes has one speaker, not three. Each header sits against
                // its own speaker's edge, so they mirror.
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

    /// One box, with its own copy button in the top-right corner.
    ///
    /// Per box rather than per turn: a reply that split into prose, a table and
    /// a command is three things you might want separately, and the command on
    /// its own is the one you actually paste.
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
                // Its own message, with no bubble around it: a table and a
                // fenced block each already have a border, a fill and their own
                // sideways scroll, and a bubble around that is a second frame
                // that says nothing.
                blockView(segment)
            }
        }
        .overlay(alignment: .topTrailing) {
            if style.showsCopyButton {
                // The `hover ==` test lives inside this leaf, deliberately —
                // see `hover`. Building the buttons is also deferred into it,
                // so a box nobody is pointing at costs a closure and no views.
                WhenPointingAt(box: box, hover: hover) {
                    boxButtons(text: copyText(of: part), box: box, entry: entry)
                        // Straddling the corner rather than sitting inside it:
                        // over the text, the button hid the end of the first
                        // line — and the one thing a copy button must not do is
                        // cover the words you are deciding whether to copy. The
                        // room it moves into is the gutter, which is empty by
                        // construction.
                        .offset(x: 10, y: -10)
                }
            }
        }
        // Hover, not always: a button on every box at rest is three buttons in
        // a three-box answer, and none of them are what you came to read.
        .onHover { hover.report(pointerIsInside: $0, over: box) }
    }

    /// Which box the pointer is over. One value, not a flag per box: the pointer
    /// is only ever in one place, and a flag each is a set of them that can all
    /// be true at once after a fast drag.
    struct BoxID: Equatable {
        let entry: UUID
        let index: Int
    }

    /// One line of the thread, tucked against this speaker's edge.
    ///
    /// The gutter is a minimum, not a fixed width: a short message keeps its
    /// bubble small and a long one grows into the rest of the row, which is what
    /// makes the thread read as a conversation rather than as two columns.
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

    /// `secondaryFontSize`: the header is there to be found, not read, and at
    /// message size it competes with the message.
    private func header(_ entry: TranscriptEntry, style: MessageBubbleStyle) -> some View {
        HStack(spacing: 5) {
            if style.isFailure {
                // Named as the app's own failure, not as something the persona
                // said. A warning in the persona's voice reads as the character
                // being unhelpful rather than as the tool being unreachable.
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

    /// One hover target for both, so moving between them can't make the pair
    /// flicker, and so the pointer leaving either one is the same event.
    private func boxButtons(text: String, box: BoxID, entry: TranscriptEntry) -> some View {
        HStack(spacing: 2) {
            pinButton(text: text, entry: entry)
            copyButton(text: text, box: box)
        }
    }

    /// Pulls this box out into its own floating window, which then survives the
    /// chat being closed and the conversation moving on.
    ///
    /// The title is the speaker and the time, which is what tells two pinned
    /// panes apart in the menu — the body is already visible in the window.
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

    /// It sits over the corner of the box, so it is given the panel's own
    /// background behind it — over a line of text with no backing, an icon is
    /// unreadable and looks like a rendering fault.
    private func copyButton(text: String, box: BoxID) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            confirmCopy(of: box)
        } label: {
            // A tick in place of the icon is fine *here*, unlike in the header:
            // the button only exists while the pointer is on the box, so it
            // can't be left looking as though it went away.
            Image(systemName: hover.copied == box ? "checkmark" : "doc.on.doc")
                .font(.system(size: appearance.settings.secondaryFontSize))
                .foregroundStyle(theme.mutedText.color)
                .padding(4)
                .background(theme.chipFill.color, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Copy this box")
    }

    /// Shows the tick, then takes it away again. Held only briefly: it says
    /// "that press worked", and a tick still sitting there ten minutes later
    /// says something else.
    private func confirmCopy(of box: BoxID) {
        hover.copied = box
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if hover.copied == box { hover.copied = nil }
        }
    }

    /// The fill is the panel's own accent and secondary, not a new palette —
    /// the point of the change is the shape of the conversation, not a different
    /// look.
    private func proseBubble(
        _ segments: [TranscriptSegment],
        style: MessageBubbleStyle
    ) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if case .text(let body) = segment {
                        // AppKit-backed: SwiftUI's Text draws links but doesn't
                        // open them from a non-activating panel, and can't show
                        // a pointer or a hover underline over them.
                        // Capped at the width the text would take unwrapped, so
                        // a short message keeps a short bubble. Without the cap
                        // every bubble — "ok?" included — is as wide as the row
                        // allows, and the two sides read as columns rather than
                        // as a conversation. A long message asks for more than
                        // the row has and simply gets the row.
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

    /// How far a bubble's text sits in from the bubble's edge — and, because a
    /// bubble starts at the edge of the thread, how far in from the thread the
    /// Secretary's words begin. The activity line is indented by the same amount
    /// so the two start in one column.
    private static let bubbleTextInset: Double = 14

    /// Yours is tinted with the accent, the Secretary's with the same neutral
    /// the rest of the panel uses. Both are faint: the text has to stay the
    /// loudest thing in the bubble.
    private func bubbleFill(_ style: MessageBubbleStyle) -> Color {
        if style.isFailure { return theme.warningFill.color }
        return (style.isMine ? theme.bubbleMine : theme.bubbleTheirs).color
    }

    /// Monospaced and scrolled sideways rather than wrapped: wrapping a line of
    /// JSON or a shell command puts a break where none exists, and the reader
    /// can no longer tell what would actually be typed. Same treatment as a
    /// wide table — the block scrolls, the conversation doesn't.
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
                // Plain text, not `inlineMarkdown`: inside a code block an
                // asterisk is an asterisk, and a backtick is a backtick.
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

    /// Cells use the body text size, not a smaller caption: a table is content,
    /// so it has to grow with +/- like the rest of the answer. Only the table
    /// scrolls sideways — the conversation itself must not, or every wide answer
    /// would drag the whole thread off screen.
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
            // Cells size to their content; the scroll view provides the room.
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

    /// Cells routinely contain `**bold**`, `` `code` `` and links. Shared with
    /// the message body so a URL is clickable wherever it appears.
    private func inlineMarkdown(_ text: String) -> AttributedString {
        MessageMarkdown.attributed(text)
    }

    /// No box, no border, no fill — it still has to read as the app talking
    /// about itself rather than as part
    /// of an answer, and now that is carried by the type alone: dimmer, smaller,
    /// with the "Working" label above it. A box did the same job louder, and
    /// stacked a frame inside a thread that is already made of frames.
    ///
    /// Left-aligned, and started at exactly the column the Secretary's words
    /// start at — the bubble's own horizontal padding, shared as a constant so
    /// the two can't drift a point apart and leave the thread looking ragged.
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


/// Everything about the conversation's *appearance* that is not carried by the
/// entries themselves.
///
/// Its whole job is to be compared. Anything that changes how a message is
/// drawn, and is not part of `TranscriptEntry`, has to be a field here or the
/// transcript will keep the look it last drew until the next message arrives.
struct TranscriptLook: Equatable {
    let fontSize: Double
    let secondaryFontSize: Double
    let font: FontChoice
    let width: Double
    let theme: ThemeChoice
    let liquidGlass: Bool
    let systemIsDark: Bool
}

/// The messages, rebuilt only when the messages or their look have changed.
///
/// **This is a performance fix with a measurement behind it** (2026-08-20, the
/// owner: "เวลาพิมพ์ใน text ของ chat window มันหน่วงๆ"). `draft` is `@State` on
/// `ChatPanelView`, so every keystroke re-evaluates that view's whole body —
/// and the body holds this list, eagerly, one view per message. Sampling the
/// app while typing put 1130 of ~1910 layout samples under
/// `ForEachChild.updateValue()`, laying the conversation out again from the
/// top: CoreText, `liblangid`, and `libThaiTokenizer` re-tokenising every Thai
/// message in the thread. It gets worse the longer the conversation, which is
/// exactly how it feels.
///
/// `.equatable()` is what stops it: when the parent re-renders and nothing here
/// has changed, the rows are left exactly as they are.
///
/// **What this does not put at risk.** An `@Observable` read *inside* a row
/// still invalidates that row directly — being skipped from above is not the
/// same as being detached — which is why hovering still works: `hover` is a
/// `BoxHover` object read only in the `WhenPointingAt` leaves. What would go
/// stale is a plain `@State` of the parent read inside a message; there is
/// none, and `partsCache` is keyed by the entry's id and text, both of which
/// are in `entries`.
private struct TranscriptRows<Row: View>: View, Equatable {
    let entries: [TranscriptEntry]
    let look: TranscriptLook
    @ViewBuilder let row: (TranscriptEntry) -> Row

    /// The closure is deliberately not compared — it is rebuilt on every parent
    /// render and would never be equal, which would defeat the whole thing. It
    /// reads nothing that `entries` and `look` do not already carry.
    static func == (lhs: TranscriptRows, rhs: TranscriptRows) -> Bool {
        lhs.entries == rhs.entries && lhs.look == rhs.look
    }

    var body: some View {
        ForEach(entries) { entry in row(entry) }
    }
}
