import SwiftUI
import Observation
import SecretaryCore

@MainActor
@Observable
final class BoxHover {
    var pointingAt: ChatPanelView.BoxID?
    var copied: ChatPanelView.BoxID?

    func report(pointerIsInside: Bool, over box: ChatPanelView.BoxID) {
        set(hoverClaim(current: pointingAt, box: box, pointerIsInside: pointerIsInside))
    }

    private func set(_ claim: ChatPanelView.BoxID?) {
        guard claim != pointingAt else { return }
        pointingAt = claim
    }
}

struct WhenPointingAt<Content: View>: View {
    let box: ChatPanelView.BoxID
    let hover: BoxHover
    @ViewBuilder let content: () -> Content

    var body: some View {
        if hover.pointingAt == box { content() }
    }
}
