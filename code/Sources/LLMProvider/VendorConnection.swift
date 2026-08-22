import FunctionalCore
import Foundation

public enum VendorConnection: Equatable, Sendable {
    case unchecked
    case checking
    case connected(String)
    case failed(String)
}

public enum VendorExecutable: Equatable, Sendable {
    case searching
    case missing(searched: [String])
    case found(AgentInstallation)
}

public enum VendorProbe: Equatable, Sendable {
    case notRun
    case signedIn(detail: String)
    case refused(String)
}

public func vendorConnection(
    vendor: AIVendor,
    executable: VendorExecutable,
    probe: VendorProbe
) -> VendorConnection {
    switch executable {
    case .searching:
        return .checking
    case .missing(let searched):
        return .failed(missingExecutableMessage(vendor: vendor, searched: searched))
    case .found(let installation):
        return connectionAfterFinding(vendor: vendor, installation: installation, probe: probe)
    }
}

func missingExecutableMessage(vendor: AIVendor, searched: [String]) -> String {
    let placesLookedIn = searched.isEmpty
        ? ""
        : " Looked in: \(searched.joined(separator: ", "))."
    return vendor.executableIsUserSupplied
        ? "\(vendor.displayName) isn't at the path given. Check the CLI path setting.\(placesLookedIn)"
        : "\(vendor.displayName) isn't installed, or isn't where the app looked.\(placesLookedIn)"
}

private func connectionAfterFinding(
    vendor: AIVendor,
    installation: AgentInstallation,
    probe: VendorProbe
) -> VendorConnection {
    switch probe {
    case .notRun:
        return .checking
    case .refused(let reason):
        return .failed(reason)
    case .signedIn(let detail):
        return .connected(connectedSummary(vendor: vendor, installation: installation, probe: detail))
    }
}

func connectedSummary(vendor: AIVendor, installation: AgentInstallation, probe detail: String) -> String {
    let parts = [
        vendor.displayName,
        Option.fromOptional(installation.version).map(versionNumber)^.getOrElse(""),
        detail
    ]
    return parts
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
}

func versionNumber(_ reported: String) -> String {
    Option.fromOptional(reported.split(separator: " ").first)
        .map(String.init)^
        .getOrElse(reported)
}

public extension VendorConnection {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .unchecked: return nil
        case .checking: return "Checking…"
        case .connected(let summary): return summary
        case .failed(let reason): return reason
        }
    }
}
