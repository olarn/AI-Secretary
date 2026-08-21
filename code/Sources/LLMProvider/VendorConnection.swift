import FunctionalCore
import Foundation

/// Whether the app can actually reach the maker it is configured to use.
///
/// Kept apart from `ClaudeCodeAvailability`, which answers a narrower question —
/// is the binary on disk. Those two were treated as the same question and they
/// are not: a Claude Code that is installed but signed out reported "Ready", and
/// the user only found out it wasn't when a turn came back refused. Finding the
/// executable is necessary and not sufficient, so the answer here is built from
/// both halves.
public enum VendorConnection: Equatable, Sendable {
    /// Nothing has been asked yet.
    case unchecked
    /// Asking now — the search or the probe is still running.
    case checking
    /// Reached it. The text is what to show beside the tick.
    case connected(String)
    /// Could not reach it, and why, in words a person can act on.
    case failed(String)
}

/// What looking for the executable came back with, without naming a maker.
public enum VendorExecutable: Equatable, Sendable {
    case searching
    case missing(searched: [String])
    case found(AgentInstallation)
}

/// What asking the tool who it is signed in as came back with.
///
/// Both payloads are already-human text: classifying a maker's stderr is that
/// maker's business, so the adapter does it and hands the sentence over. That is
/// what keeps the decision below free of any one CLI's error vocabulary.
public enum VendorProbe: Equatable, Sendable {
    case notRun
    /// Reached and signed in. The detail is an extra fact worth showing — the
    /// plan tier, say — and may be empty when there is nothing to add.
    case signedIn(detail: String)
    case refused(String)
}

/// The whole decision, as one table.
///
/// Five inputs, and the order they are tested in is the point: a missing
/// executable outranks any probe result, because a probe that never ran cannot
/// tell you anything and saying "not signed in" about a tool that isn't
/// installed sends the user to fix the wrong thing.
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

/// Worded like a form's required-field message: what is wrong, then what to do.
/// The places looked in are listed because "not installed" is wrong nearly as
/// often as it is right — it is usually installed somewhere unusual.
func missingExecutableMessage(vendor: AIVendor, searched: [String]) -> String {
    let where_ = searched.isEmpty
        ? ""
        : " Looked in: \(searched.joined(separator: ", "))."
    return vendor.executableIsUserSupplied
        ? "\(vendor.displayName) isn't at the path given. Check the CLI path setting.\(where_)"
        : "\(vendor.displayName) isn't installed, or isn't where the app looked.\(where_)"
}

private func connectionAfterFinding(
    vendor: AIVendor,
    installation: AgentInstallation,
    probe: VendorProbe
) -> VendorConnection {
    switch probe {
    case .notRun:
        // Found but unasked is still "checking", never a tick: the tick has to
        // mean the app got an answer back, or it is the same false "Ready" this
        // type exists to replace.
        return .checking
    case .refused(let reason):
        return .failed(reason)
    case .signedIn(let detail):
        return .connected(connectedSummary(vendor: vendor, installation: installation, probe: detail))
    }
}

/// Name, then version, then whatever the probe added — each part dropped when
/// it is not known, so the line never reads "Claude Code  · ".
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

/// Just the number out of what the tool answered.
///
/// `claude --version` replies `2.1.238 (Claude Code)`, and the maker's name is
/// already the first thing on this line — printed whole it read
/// "Claude Code · 2.1.238 (Claude Code) · Max". Taking the leading token is
/// enough for every version string seen so far and degrades to the whole string
/// for one that has no space in it.
func versionNumber(_ reported: String) -> String {
    Option.fromOptional(reported.split(separator: " ").first)
        .map(String.init)^
        .getOrElse(reported)
}

public extension VendorConnection {
    /// For the view, which paints a tick, a cross, or neither, and must not
    /// pattern-match a domain enum to decide.
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

    /// The line to show, whichever way it went. Absent only before anything has
    /// been asked, where the row shows nothing at all.
    var message: String? {
        switch self {
        case .unchecked: return nil
        case .checking: return "Checking…"
        case .connected(let summary): return summary
        case .failed(let reason): return reason
        }
    }
}
