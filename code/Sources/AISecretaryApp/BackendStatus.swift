import Foundation
import Observation
import LLMProvider

@MainActor
@Observable
final class BackendStatus {
    var availability: ClaudeCodeAvailability?

    private(set) var connection: VendorConnection = .unchecked

    let runtime: VendorRuntime

    init(runtime: VendorRuntime = .claudeCode) {
        self.runtime = runtime
    }

    var isChecking: Bool { availability == nil }

    var installation: ClaudeCodeInstallation? { availability?.installation }

    var needsOnboarding: Bool {
        if case .notFound = availability { return true }
        return false
    }

    var vendorName: String { runtime.vendor.displayName }

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
