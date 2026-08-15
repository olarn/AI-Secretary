import AppKit
import SwiftUI
import SecretaryCore

/// The keyboard's second meanings: the choice picker, history recall, and the
/// event monitors that see keys and wheels before the responder chain does —
/// which is the only reliable point, as the doc comments below record. Split
/// out of `ChatPanelView.swift` along the seam the file already had; nothing
/// here changed in the move.
extension ChatPanelView {
    /// What you've sent this session, oldest first.
    ///
    /// Read back out of the transcript rather than kept in a second list: the
    /// transcript already is the record, and a copy of it would be one more
    /// thing to keep in step. It also means recall covers exactly one session,
    /// which is what was asked for.
    private var sentMessages: [String] {
        secretary.transcript
            .filter { $0.speaker == .user && $0.kind == .message }
            .map(\.text)
    }

    /// Whether the arrows should act as history rather than move the caret.
    private var canRecall: Bool {
        !draft.contains("\n") && !sentMessages.isEmpty
    }

    /// The options the assistant is waiting on, if its latest message asked
    /// something. Only the latest: an older question has been overtaken.
    private var pendingChoices: [String] {
        guard machine.state == .idle,
              let last = secretary.transcript.last,
              last.speaker == .secretary, last.kind == .message
        else { return [] }
        return MessageChoices.parse(last.text).options
    }

    /// The question's answers, as a list you can walk with the arrow keys and
    /// take with Return — or simply click, since a keyboard-only control in a
    /// window you reach with the mouse would be a trap.
    @ViewBuilder
    var choiceList: some View {
        let options = pendingChoices
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Button { pick(option) } label: {
                        HStack(alignment: .top, spacing: 6) {
                            // The caret marks the highlight for anyone who
                            // can't tell the tint apart from the background.
                            Text(index == choiceIndex ? "›" : " ")
                                .fontWeight(.bold)
                            Text(option)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(
                            size: appearance.settings.fontSize,
                            design: appearance.settings.font.swiftUIDesign
                        ))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(
                            index == choiceIndex ? theme.accentFill.color : .clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // Says who the arrows currently belong to, because a key that
                // silently means two things is the part people get wrong.
                Text(
                    draft.isEmpty
                        ? "↑ ↓ to move · return to choose"
                        : "typing your own answer · ↑ ↓ recall sent messages"
                )
                .font(.system(size: appearance.settings.secondaryFontSize))
                .foregroundStyle(theme.mutedText.color)
                .padding(.horizontal, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .onAppear { choiceIndex = 0 }
            // A new question replaces the old options in place, without the
            // list ever leaving the screen, so `onAppear` doesn't fire again.
            .onChange(of: options) { choiceIndex = 0 }
        }
    }

    /// Answering sends the option's own words, not "A" or "the second one":
    /// the model reads it as an ordinary reply, and the transcript records what
    /// was actually chosen.
    private func pick(_ option: String) {
        choiceIndex = 0
        draft = ""
        scrollPin.follow()
        secretary.submit(option)
    }

    /// Catches Up and Down before the text field turns them into caret
    /// movement.
    ///
    /// `.onKeyPress` was the obvious way and does not work here: Return
    /// arrives, the arrows never do, because the field consumes them as
    /// `moveUp:`/`moveDown:` first. Verified in the running app — the handler
    /// was in place and the box stayed empty. A local event monitor sees the
    /// key before the responder chain does, which is the only reliable point.
    func startWatchingArrowKeys() {
        guard arrowKeyMonitor == nil else { return }
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.isDisjoint(with: [.command, .option, .control])
            else { return event }
            // Escape is deliberately not handled here. It used to be, because
            // `.onExitCommand` never fired on this non-activating panel — but
            // this view is built once and never torn down, so the monitor
            // outlived the panel it was closing and swallowed Esc for the whole
            // app whether the chat was showing or not. Esc now has a single
            // owner in `AppDelegate`, over one ladder in `dismissDecision`,
            // because it means three different things depending on what is on
            // screen and a key that means three things needs one place to say
            // which.
            //
            // 126 is Up, 125 is Down. Which feature they belong to is decided
            // in one place — see `ArrowKeyOwner` — so the picker, history
            // recall and caret movement can never each take a turn at the same
            // keystroke.
            let options = pendingChoices
            switch ArrowKeyOwner.owner(
                hasChoices: !options.isEmpty,
                draft: draft,
                hasHistory: !sentMessages.isEmpty
            ) {
            case .choiceList:
                // Clamped at use: a second question can arrive while the list
                // is still up, and a highlight left pointing past a shorter
                // list would trap on Return.
                let highlighted = min(choiceIndex, options.count - 1)
                switch event.keyCode {
                case 126:
                    choiceIndex = max(0, highlighted - 1)
                    return nil
                case 125:
                    choiceIndex = min(options.count - 1, highlighted + 1)
                    return nil
                case 36:
                    pick(options[highlighted])
                    return nil
                default: return event
                }
            case .history:
                // Recall stays tied to the caret being in the box: it edits
                // what you are typing, so it needs you to be typing.
                guard messageBoxFocused else { return event }
                switch event.keyCode {
                case 126: return recallOlder() ? nil : event
                case 125: return recallNewer() ? nil : event
                default: return event
                }
            case .textCaret:
                return event
            }
        }
    }

    /// Notices the reader scrolling back through the conversation, so a reply
    /// still arriving stops chasing them down the page.
    ///
    /// From the event rather than from the scroll position, because a position
    /// cannot say who moved it: the content growing under a reader who hasn't
    /// touched anything looks exactly like the reader scrolling up. The event
    /// only exists when they did it. Never consumed — it is passed straight
    /// through and the view scrolls as usual.
    func startWatchingScroll() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard pointerOverTranscript,
                  readerIsScrollingBack(scrollingDeltaY: event.scrollingDeltaY),
                  scrollPin.isFollowing
            else { return event }
            scrollPin.readerScrolledUp()
            return event
        }
    }

    func stopWatchingScroll() {
        scrollMonitor.map(NSEvent.removeMonitor)
        scrollMonitor = nil
    }

    func stopWatchingArrowKeys() {
        arrowKeyMonitor.map(NSEvent.removeMonitor)
        arrowKeyMonitor = nil
    }

    /// Steps back towards older messages. Returns whether it took the key.
    private func recallOlder() -> Bool {
        guard canRecall else { return false }
        let history = sentMessages
        switch recallIndex {
        case nil:
            stashedDraft = draft
            recallIndex = history.count - 1
        case let index? where index > 0:
            recallIndex = index - 1
        default:
            // Already at the oldest. Take the key anyway, so it stops here
            // rather than jumping the caret somewhere unexpected.
            return true
        }
        draft = recallIndex.map { history[$0] } ?? draft
        return true
    }

    /// Steps forward towards what you were typing.
    private func recallNewer() -> Bool {
        guard let index = recallIndex else { return false }
        let history = sentMessages
        if index + 1 < history.count {
            recallIndex = index + 1
            draft = history[index + 1]
        } else {
            recallIndex = nil
            draft = stashedDraft
        }
        return true
    }

    func send() {
        let text = draft
        draft = ""
        // A sent message ends the walk: the next Up starts again from the end,
        // the way a shell behaves.
        recallIndex = nil
        stashedDraft = ""
        scrollPin.follow()
        secretary.submit(text)
    }
}
