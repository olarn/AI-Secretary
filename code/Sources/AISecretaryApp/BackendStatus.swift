import Foundation
import Observation
import LLMProvider

/// What the UI knows about where work will run.
///
/// Detection can involve launching a login shell, so it happens on a background
/// task after launch and this object is how the result reaches the views. `nil`
/// means "still looking" — the panel shows neither the onboarding card nor a
/// confirmed backend until we actually know.
@MainActor
@Observable
final class BackendStatus {
    var availability: ClaudeCodeAvailability?

    /// Whether the maker can actually be reached, which is a different question
    /// from whether its tool is on disk — see `VendorConnection`.
    private(set) var connection: VendorConnection = .unchecked

    /// Which maker the app is set up to use. One today; this is the value the
    /// vendor picker will write.
    let runtime: VendorRuntime

    init(runtime: VendorRuntime = .claudeCode) {
        self.runtime = runtime
    }

    var isChecking: Bool { availability == nil }

    var installation: ClaudeCodeInstallation? { availability?.installation }

    /// True only once we've looked and found nothing.
    var needsOnboarding: Bool {
        if case .notFound = availability { return true }
        return false
    }

    var vendorName: String { runtime.vendor.displayName }

    /// Asks the maker whether it can be reached, and publishes the answer.
    ///
    /// Every state it can be in is produced by `vendorConnection`, so this
    /// method chooses nothing — it gathers the two inputs and applies the
    /// answer. That is deliberate: `AISecretaryApp` is never linked into the
    /// test bundle, so a rule decided here would be a rule no test can see.
    func checkConnection() {
        guard let availability else {
            connection = vendorConnection(
                vendor: runtime.vendor, executable: .searching, probe: .notRun
            )
            return
        }
        switch availability {
        case .notFound(let searched):
            connection = vendorConnection(
                vendor: runtime.vendor, executable: .missing(searched: searched), probe: .notRun
            )
        case .available(let installation):
            let found = installation.agent
            connection = vendorConnection(
                vendor: runtime.vendor, executable: .found(found), probe: .notRun
            )
            Task { [runtime] in
                let probe = await runtime.probe(found)
                self.connection = vendorConnection(
                    vendor: runtime.vendor, executable: .found(found), probe: probe
                )
            }
        }
    }
}
