import SwiftUI
import Observation
import SecretaryCore

/// Which box in the transcript the pointer is on, and which was last copied.
///
/// A reference type rather than two `@State` values on the panel, for one
/// reason: with `@Observable`, a view is subscribed to exactly the properties
/// it *reads*. Keeping these here lets the panel own them and hand them to the
/// leaf that draws the buttons, without the panel itself being invalidated when
/// they change — which is what scrolling a long thread does, repeatedly, as
/// each box slides under a stationary pointer.
///
/// It holds two values and applies one rule; the rule itself is
/// `hoverClaim`, in `SecretaryCore`, where it can be tested.
@MainActor
@Observable
final class BoxHover {
    var pointingAt: ChatPanelView.BoxID?
    var copied: ChatPanelView.BoxID?

    /// The box's one `.onHover`. Only the box calls this — see `hoverClaim`
    /// for why the buttons must not.
    func report(pointerIsInside: Bool, over box: ChatPanelView.BoxID) {
        set(hoverClaim(current: pointingAt, box: box, pointerIsInside: pointerIsInside))
    }

    private func set(_ claim: ChatPanelView.BoxID?) {
        // Assigning an unchanged value would still notify every observer, and
        // a sweep across the thread delivers plenty of events that change
        // nothing.
        guard claim != pointingAt else { return }
        pointingAt = claim
    }
}

/// Draws `content` only while the pointer is on `box`.
///
/// This exists to be a leaf. The comparison against `hover.pointingAt` has to
/// happen somewhere, and wherever it happens is what gets rebuilt on every
/// hover change — so it happens here, in a view whose entire body is an `if`,
/// rather than in the panel, whose body rebuilds sixty messages.
struct WhenPointingAt<Content: View>: View {
    let box: ChatPanelView.BoxID
    let hover: BoxHover
    @ViewBuilder let content: () -> Content

    var body: some View {
        if hover.pointingAt == box { content() }
    }
}
