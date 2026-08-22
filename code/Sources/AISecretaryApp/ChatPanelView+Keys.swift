import AppKit
import SwiftUI
import SecretaryCore

extension ChatPanelView {
    private var sentMessages: [String] {
        secretary.transcript
            .filter { $0.speaker == .user && $0.kind == .message }
            .map(\.text)
    }

    private var canRecall: Bool {
        !draft.contains("\n") && !sentMessages.isEmpty
    }

    private var pendingChoices: [String] {
        guard machine.state == .idle,
              let last = secretary.transcript.last,
              last.speaker == .secretary, last.kind == .message
        else { return [] }
        return MessageChoices.parse(last.text).options
    }

    @ViewBuilder
    var choiceList: some View {
        let options = pendingChoices
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Button { pick(option) } label: {
                        HStack(alignment: .top, spacing: 6) {
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
            .onChange(of: options) { choiceIndex = 0 }
        }
    }

    private func pick(_ option: String) {
        choiceIndex = 0
        draft = ""
        scrollPin.follow()
        secretary.submit(option)
    }

    func startWatchingArrowKeys() {
        guard arrowKeyMonitor == nil else { return }
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.isDisjoint(with: [.command, .option, .control])
            else { return event }
            let options = pendingChoices
            switch ArrowKeyOwner.owner(
                hasChoices: !options.isEmpty,
                draft: draft,
                hasHistory: !sentMessages.isEmpty
            ) {
            case .choiceList:
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
            return true
        }
        draft = recallIndex.map { history[$0] } ?? draft
        return true
    }

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
        recallIndex = nil
        stashedDraft = ""
        scrollPin.follow()
        secretary.submit(text)
    }
}
