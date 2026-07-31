import Foundation
import Observation
import FunctionalCore
import LLMProvider
import SecretaryCore

/// Keeps the plan-limit figures current while the usage window is open.
///
/// Each refresh is a short-lived `claude -p -- /usage`, so it is polled rather
/// than streamed, and only while someone is looking: the timer starts when the
/// window opens and stops when it closes. A companion that shells out every two
/// minutes forever, to draw a bar nobody is watching, is not a companion.
@MainActor
@Observable
final class PlanUsageModel {
    private(set) var usage: PlanUsage?
    private(set) var isRefreshing = false
    /// Set when the figures could not be read. Shown instead of a number,
    /// never in place of one — a stale percentage presented as current is the
    /// failure this whole class is trying to avoid.
    private(set) var problem: String?

    @ObservationIgnored private let backend: ChatBackend
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    /// Read once. The subscription tier does not change while the app is open,
    /// and asking on every poll would run a second process for a fixed string.
    @ObservationIgnored private var planName: String?

    /// Often enough that the bar is not misleading, rarely enough that it is not
    /// a background job. The windows it tracks are five hours and a week long.
    static let pollInterval: Duration = .seconds(120)

    init(backend: ChatBackend) {
        self.backend = backend
    }

    func startPolling() {
        refresh()
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: PlanUsageModel.pollInterval)
                if Task.isCancelled { return }
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        // Single-flight: the poll and the refresh button can land together, and
        // two processes would race to set the same numbers.
        guard inFlight == nil else { return }
        guard case .available(let installation)? = backend.availability else {
            problem = "Claude Code isn't available, so plan limits can't be read."
            return
        }
        isRefreshing = true
        inFlight = Task { [weak self] in
            if self?.planName == nil {
                let identity = await PlanUsageProbe.readIdentity(installation: installation)
                self?.planName = identity.fold({ _ in nil }, PlanIdentityParser.planName(fromAuthStatus:))
            }
            let result = await PlanUsageProbe.read(installation: installation)
            guard let self else { return }
            self.isRefreshing = false
            self.inFlight = nil
            result.fold(
                { error in self.problem = error.errorDescription ?? "Couldn't read plan limits." },
                { text in
                    guard var parsed = PlanUsageParser.parse(text) else {
                        // Recognising nothing usually means Claude Code changed
                        // its wording. Say so rather than showing the last
                        // reading as if it were new.
                        self.problem = "Couldn't read the plan limits from Claude Code's reply."
                        return
                    }
                    // Carried over so the tier does not blink out on a refresh
                    // whose identity lookup happened to fail.
                    parsed = parsed.named(self.planName ?? self.usage?.planName)
                    self.usage = parsed
                    self.problem = nil
                }
            )
        }
    }
}
