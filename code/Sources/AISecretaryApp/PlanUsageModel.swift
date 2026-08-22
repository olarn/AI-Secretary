import Foundation
import Observation
import FunctionalCore
import LLMProvider
import SecretaryCore

@MainActor
@Observable
final class PlanUsageModel {
    private(set) var usage: PlanUsage?
    private(set) var isRefreshing = false
    private(set) var problem: String?

    @ObservationIgnored private let backend: ChatBackend
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var planName: String?

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
                        self.problem = "Couldn't read the plan limits from Claude Code's reply."
                        return
                    }
                    parsed = parsed.named(self.planName ?? self.usage?.planName)
                    self.usage = parsed
                    self.problem = nil
                }
            )
        }
    }
}
