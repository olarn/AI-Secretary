import Foundation

/// How the character breathes while the assistant is busy, as numbers rather
/// than as animation code.
///
/// The halo and the badge are drawn in `AISecretaryApp`, which is never linked
/// into the test bundle, so the *rule* — which states breathe, how far, and how
/// fast — lives here where a test can read it.
public struct StatusPulse: Equatable, Sendable {
    /// How large the badge grows at the top of the breath, as a multiplier.
    /// The halo does not scale: it is the frame the character sits in, and a
    /// frame that changes size moves the character inside it.
    public let peakScale: Double

    /// Seconds for one full breath, out and back.
    public let period: Double

    public init(peakScale: Double, period: Double) {
        self.peakScale = peakScale
        self.period = period
    }

    /// What every state that isn't busy gets: full size, its own colour, and no
    /// clock running. A character that keeps moving after the work is finished
    /// says the work is not finished.
    public static let still = StatusPulse(peakScale: 1, period: 0)

    /// One rhythm for the whole of "she is doing something". 10% is the size
    /// step the owner asked for — big enough to catch the eye at 22pt across,
    /// small enough that it doesn't shove the character's shoulder about.
    public static let busy = StatusPulse(peakScale: 1.1, period: 1.2)

    /// Whether there is anything to animate. Both halves matter: a pulse that
    /// changes nothing, and a pulse with no time to change it in, are equally
    /// still.
    public var isAnimated: Bool { period > 0 && peakScale != 1 }
}

/// Whether the character breathes, and how, for a given state.
///
/// Tied to `isBusy` rather than to a per-state table: thinking and working are
/// the two states the person is waiting through, and a table with a row per
/// state is a row somebody has to remember to add. The owner wrote the request
/// against thinking; working is the same wait with a tool attached, and giving
/// it a different rhythm would say something that isn't true.
public func statusPulse(for state: AssistantState) -> StatusPulse {
    state.isBusy ? .busy : .still
}

/// Where in the breath we are at a given moment: 0 at rest, 1 fully expanded,
/// eased at both ends by a cosine so there is no corner at the turn.
///
/// **A function of the clock, not of a stored flag, and that is the whole
/// point.** The first version toggled an `@State` bool under a `repeatForever`
/// animation; it kept breathing after the answer had arrived and the state was
/// back to idle, because a repeating SwiftUI animation outlives the value that
/// started it. Measured, not guessed: three captures of the character window a
/// second apart, all in idle, and the badge region differed in every pair.
/// Reading the phase from the current time has no such state to get stuck in —
/// when the pulse is `.still` the answer is 0 for every possible moment.
///
/// `seconds` is an absolute time, not an elapsed one, so the halo and the badge
/// can compute it separately and still be in step: same input, same output.
public func pulseProgress(_ pulse: StatusPulse, at seconds: Double) -> Double {
    guard pulse.isAnimated else { return 0 }
    return (1 - cos(2 * .pi * seconds / pulse.period)) / 2
}

/// The badge's size at that moment, as a multiplier of its resting size.
public func pulseScale(_ pulse: StatusPulse, at seconds: Double) -> Double {
    1 + (pulse.peakScale - 1) * pulseProgress(pulse, at: seconds)
}
