import Foundation

/// How the status badge breathes, as numbers rather than as animation code.
///
/// The badge is drawn in `AISecretaryApp`, which is never linked into the test
/// bundle, so the *rule* — which states breathe, how far, and how fast — lives
/// here where a test can read it. The view only applies the answer, and can be
/// wrong in one way (the animation never starting), which is a thing you have
/// to look at rather than assert.
public struct StatusPulse: Equatable, Sendable {
    /// How large the badge grows at the top of the breath, as a multiplier.
    public let peakScale: Double

    /// How faint the fill goes at the same moment. The white ring and the glyph
    /// keep their full strength: what was asked for is the *colour* going dark
    /// and light, and fading the whole badge would take the outline with it.
    public let dimOpacity: Double

    /// Seconds for one full breath, out and back.
    public let period: Double

    public init(peakScale: Double, dimOpacity: Double, period: Double) {
        self.peakScale = peakScale
        self.dimOpacity = dimOpacity
        self.period = period
    }

    /// What every state that isn't busy gets: full size, full colour, and no
    /// clock running. A badge that keeps moving after the work is finished says
    /// the work is not finished.
    public static let still = StatusPulse(peakScale: 1, dimOpacity: 1, period: 0)

    /// One rhythm for the whole of "she is doing something". 10% is the size
    /// step the owner asked for — big enough to catch the eye at 22pt across,
    /// small enough that it doesn't shove the character's shoulder about.
    public static let busy = StatusPulse(peakScale: 1.1, dimOpacity: 0.55, period: 1.2)

    /// Whether there is anything to animate. Both halves matter: a pulse that
    /// changes nothing, and a pulse with no time to change it in, are equally
    /// still — and either one handed to `repeatForever` is an animation that
    /// runs for ever while doing nothing.
    public var isAnimated: Bool {
        period > 0 && (peakScale != 1 || dimOpacity != 1)
    }

    /// One direction of the breath — what a SwiftUI `autoreverses` animation
    /// wants as its duration, since it plays the return leg itself. Named here
    /// rather than divided by two at the call site, so the period stays the
    /// number that means what it says.
    public var halfCycle: Double { period / 2 }
}

/// Whether the badge breathes, and how, for a given state.
///
/// Tied to `isBusy` rather than to a per-state table: thinking and working are
/// the two states the person is waiting through, and a table with a row per
/// state is a row somebody has to remember to add. The owner wrote the request
/// against thinking; working is the same wait with a tool attached, and giving
/// it a different rhythm would say something that isn't true.
public func statusPulse(for state: AssistantState) -> StatusPulse {
    state.isBusy ? .busy : .still
}
