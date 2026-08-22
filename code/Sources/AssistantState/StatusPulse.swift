import Foundation

public struct StatusPulse: Equatable, Sendable {
    public let peakScale: Double
    public let period: Double

    public init(peakScale: Double, period: Double) {
        self.peakScale = peakScale
        self.period = period
    }

    public static let still = StatusPulse(peakScale: 1, period: 0)

    public static let busy = StatusPulse(peakScale: 1.1, period: 1.2)

    public var isAnimated: Bool { period > 0 && peakScale != 1 }
}

public func statusPulse(for state: AssistantState) -> StatusPulse {
    state.isBusy ? .busy : .still
}

public func pulseProgress(_ pulse: StatusPulse, at absoluteSeconds: Double) -> Double {
    guard pulse.isAnimated else { return 0 }
    return (1 - cos(2 * .pi * absoluteSeconds / pulse.period)) / 2
}

public func pulseScale(_ pulse: StatusPulse, at absoluteSeconds: Double) -> Double {
    1 + (pulse.peakScale - 1) * pulseProgress(pulse, at: absoluteSeconds)
}
