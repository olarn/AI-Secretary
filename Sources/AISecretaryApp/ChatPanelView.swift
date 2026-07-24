import SwiftUI
import AssistantState

/// Mock chat/task panel: lets the user manually walk the state machine
/// through its transitions to demonstrate the lifecycle. No real
/// interpretation, tool execution, or network calls happen here.
///
/// Rendered as a manga-style speech bubble anchored to the character.
struct ChatPanelView: View {
    let machine: AssistantStateMachine
    let layout: ChatBubbleLayout
    let onClose: () -> Void
    @State private var lastRejection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Secretary — Mock Console")
                .font(.headline)

            Text("Current state: \(machine.state.description)")
                .font(.subheadline.monospaced())

            HStack(spacing: 8) {
                actionButton("Begin listening") {
                    send(.userBeganInput, reason: "user opened chat")
                }
                actionButton("Interpret") {
                    send(.beginInterpreting, reason: "mock intent classification")
                }
                actionButton("Execute") {
                    send(.beginExecuting, reason: "mock tool invocation", taskID: UUID().uuidString)
                }
            }

            HStack(spacing: 8) {
                actionButton("Succeed") {
                    send(.succeeded, reason: "mock tool result: success", toolStatus: "ok")
                }
                actionButton("Fail") {
                    send(.failed, reason: "mock tool result: failure", toolStatus: "error")
                }
                actionButton("Acknowledge") {
                    send(.acknowledge, reason: "user dismissed result")
                }
            }

            if let lastRejection {
                Text(lastRejection)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Text("Transition history")
                .font(.subheadline.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(machine.history.enumerated()), id: \.offset) { _, transition in
                        Text("\(transition.from.description) → \(transition.to.description)  (\(transition.reason))")
                            .font(.caption.monospaced())
                    }
                }
            }
            .frame(maxHeight: 160)
        }
        .padding(18)
        .frame(width: 340)
        .background(
            SpeechBubbleShape(isMirrored: layout.isMirrored)
                .fill(.regularMaterial)
        )
        .overlay(
            SpeechBubbleShape(isMirrored: layout.isMirrored)
                .stroke(Color.primary.opacity(0.85), lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .onExitCommand(perform: onClose)
        .frame(width: 340, height: 460, alignment: .top)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            lastRejection = nil
            action()
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    private func send(
        _ event: AssistantEvent,
        reason: String,
        taskID: String? = nil,
        toolStatus: String? = nil
    ) {
        let result = machine.send(event, reason: reason, taskID: taskID, toolStatus: toolStatus)
        if case .failure(let error) = result {
            lastRejection = "Rejected: \(error)"
        }
    }
}
