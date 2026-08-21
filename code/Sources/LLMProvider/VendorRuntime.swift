import FunctionalCore
import Foundation

/// Everything one turn needs from a maker's tool.
///
/// Composed rather than invented: the three protocols already existed and were
/// already what `ChatBackend` reached for, but only `ClaudeCodeProvider`
/// happened to satisfy all three, so the wiring named that class instead of a
/// capability. Naming the capability is what lets a second maker be plugged in
/// without `ChatBackend` learning about it.
public protocol VendorProvider: ChatProvider, WorkspaceScopedProvider, SkillInstalling {
    /// What a live session said it is actually running on.
    ///
    /// Here rather than derived from the model the app asked for, because the
    /// interesting case is the one where the app asked for nothing: the answer
    /// is then the user's own configured default, which only the tool knows.
    var reportedModel: String? { get }
}

extension ClaudeCodeProvider: VendorProvider {}

/// How to build a provider for one maker.
///
/// A value holding a function, not a subclass tree: adding a maker is adding one
/// of these, and the app's wiring stays a single injection point. The factory
/// takes the vendor-neutral installation so this type never mentions a
/// particular CLI's types — the closure converts on the way in, which is the
/// only place that conversion belongs.
public struct VendorRuntime: Sendable {
    public let vendor: AIVendor
    public let makeProvider: @Sendable (AgentInstallation) -> VendorProvider
    /// How this maker answers "can you actually be reached". A function rather
    /// than a protocol method because it is the only thing a runtime does
    /// besides build a provider, and a one-method protocol here would exist
    /// solely to be substituted in a test.
    public let probe: @Sendable (AgentInstallation) async -> VendorProbe
    /// Asks the installed tool what models it can actually run.
    ///
    /// Absent for a maker whose list is fixed and known ahead of time. Present
    /// for one where the list belongs to *this machine* — opencode answers
    /// whatever that user configured, so a list compiled into the app would be
    /// wrong for nearly everybody.
    private let discoverModels: (@Sendable (AgentInstallation) async -> [ChatModel])?
    /// Pays the first turn's cost early, for a maker where that cost is worth
    /// paying. Absent means there is nothing useful to warm — see
    /// `WarmUpTarget` for the measurements that decide which is which.
    private let warmUpTool: (@Sendable (AgentInstallation, URL?, ChatModel?) async -> Void)?

    public init(
        vendor: AIVendor,
        makeProvider: @escaping @Sendable (AgentInstallation) -> VendorProvider,
        probe: @escaping @Sendable (AgentInstallation) async -> VendorProbe,
        discoverModels: (@Sendable (AgentInstallation) async -> [ChatModel])? = nil,
        warmUpTool: (@Sendable (AgentInstallation, URL?, ChatModel?) async -> Void)? = nil
    ) {
        self.vendor = vendor
        self.makeProvider = makeProvider
        self.probe = probe
        self.discoverModels = discoverModels
        self.warmUpTool = warmUpTool
    }

    /// Whether this maker has a first-turn cost worth paying up front.
    public var warmsUp: Bool { warmUpTool != nil }

    /// Does nothing for a maker with nothing to warm, so the caller needs no
    /// branch of its own.
    public func warmUp(_ installation: AgentInstallation, directory: URL?, model: ChatModel?) async {
        await warmUpTool?(installation, directory, model)
    }

    /// What the picker should offer. The maker's own fixed list unless it has a
    /// way of asking the machine, and the fixed list again if asking came back
    /// with nothing — an empty picker is worse than a stale one.
    public func offeredModels(_ installation: AgentInstallation) async -> [ChatModel] {
        guard let discoverModels else { return vendor.models }
        let found = await discoverModels(installation)
        return found.isEmpty ? vendor.models : found
    }
}

public extension VendorRuntime {
    /// The user's own Claude Code. The default everywhere, so that adding the
    /// seam changed no behaviour on the day it was added.
    static let claudeCode = VendorRuntime(
        vendor: .claudeCode,
        makeProvider: { installation in
            ClaudeCodeProvider(
                installation: ClaudeCodeInstallation(
                    executableURL: installation.executableURL,
                    version: installation.version
                )
            )
        },
        probe: VendorRuntime.claudeCodeConnectionProbe
    )

    /// Absent for an id with no runtime wired up — a settings file naming a
    /// maker this build cannot run is a fallback, not a crash.
    static func named(_ id: String) -> Option<VendorRuntime> {
        Option.fromOptional(all.first { $0.vendor.id == id })
    }

    /// Every wired-up maker, in the same order the picker lists them.
    static let all: [VendorRuntime] = [.claudeCode, .openCode]
}

/// The per-character backend, as the orchestrator needs to see it.
///
/// Exists to replace a downcast to the concrete `ChatBackend` class, which tied
/// the orchestrator to one implementation for the sake of two read-only
/// questions. Both questions are about the maker rather than about that class,
/// so they belong on a protocol.
public protocol VendorBackend: ChatProvider {
    /// Which maker this character's work runs through.
    var vendor: AIVendor { get }
    /// What the maker is configured to use when the app asks for nothing.
    var inheritedDefaults: ClaudeCodeDefaults { get }
}
