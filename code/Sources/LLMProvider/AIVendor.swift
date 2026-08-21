import FunctionalCore
import Foundation

/// Which AI maker a character's work runs through, and what that maker can do.
///
/// The app ran on exactly one — the user's own Claude Code — and said so in
/// every layer: the model list was a constant on `ChatModel`, "does it have an
/// effort setting" was assumed rather than asked, and the one provider was
/// constructed by name inside `ChatBackend`. None of those are wrong for one
/// maker and all of them are walls in front of the second.
///
/// This type is the answer to the questions the rest of the app has to ask
/// before it can draw a settings panel or start a turn, so that adding a maker
/// is adding a value here rather than editing a `switch` in six files. It is
/// pure data on purpose: no process, no disk, no network. Finding the
/// executable is the locator's job and running it is the provider's.
public struct AIVendor: Equatable, Sendable, Identifiable {
    /// Stable across releases — it is written into settings, so renaming one
    /// silently resets everybody who had chosen it.
    public let id: String
    public let displayName: String

    /// What may be picked in the settings panel. Empty means the maker offers
    /// no choice and the panel shows no model row at all.
    public let models: [ChatModel]

    /// Whether an effort level means anything here. The backlog asks for the
    /// effort row to be hidden rather than disabled for makers without one,
    /// which needs this to be a question the panel can ask.
    public let supportsEffort: Bool

    /// Whether this maker can drive the user's browser. Only a tool that
    /// authenticates as the user can; an API-shaped backend has no way in.
    public let supportsBrowser: Bool

    /// Whether skills can be installed through it.
    public let supportsSkills: Bool

    /// Whether the user has to say where the executable is.
    ///
    /// Claude Code is looked for in known locations and found; the next maker in
    /// the backlog is handed a CLI path by the user instead. The difference
    /// decides whether the panel shows a path field, so it is asked here rather
    /// than inferred from whether the search happened to fail.
    public let executableIsUserSupplied: Bool

    public init(
        id: String,
        displayName: String,
        models: [ChatModel],
        supportsEffort: Bool,
        supportsBrowser: Bool,
        supportsSkills: Bool,
        executableIsUserSupplied: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.models = models
        self.supportsEffort = supportsEffort
        self.supportsBrowser = supportsBrowser
        self.supportsSkills = supportsSkills
        self.executableIsUserSupplied = executableIsUserSupplied
    }
}

public extension AIVendor {
    /// The user's own Claude Code — the only maker wired up today.
    ///
    /// `ChatModel.known` stays where it is and is read from here rather than
    /// moved: two lists of the same six ids is exactly the duplication that goes
    /// stale in one copy. New code asks the vendor.
    static let claudeCode = AIVendor(
        id: "claude-code",
        displayName: "Claude Code",
        models: ChatModel.known,
        supportsEffort: true,
        supportsBrowser: true,
        supportsSkills: true,
        executableIsUserSupplied: false
    )

    /// Every maker the app can run. One today; this is the list the settings
    /// panel will offer once there is a second.
    static let known: [AIVendor] = [.claudeCode]

    /// Absent rather than a crash for an id this build has never heard of — a
    /// settings file written by a later build can name one, and the caller falls
    /// back to the default instead of refusing to start.
    static func named(_ id: String) -> Option<AIVendor> {
        Option.fromOptional(known.first { $0.id == id })
    }

    /// Whether a model may be chosen for this maker. A persisted choice
    /// belonging to another maker is not an error — it simply no longer applies.
    func offers(model: ChatModel) -> Bool {
        models.contains(model)
    }
}

/// Where a maker's executable is, without saying which maker found it.
///
/// `ClaudeCodeInstallation` carries the same two facts and stays exactly as it
/// is. This is the shape the vendor-neutral half of the app passes around, so
/// the provider factory does not have to name Claude's type in order to build a
/// provider — which is the whole point of the factory.
public struct AgentInstallation: Equatable, Sendable {
    public let vendorID: String
    public let executableURL: URL
    /// Reported by the tool itself, when it could be read.
    public let version: String?

    public init(vendorID: String, executableURL: URL, version: String? = nil) {
        self.vendorID = vendorID
        self.executableURL = executableURL
        self.version = version
    }
}

public extension ClaudeCodeInstallation {
    /// The vendor-neutral view of this installation.
    var agent: AgentInstallation {
        AgentInstallation(
            vendorID: AIVendor.claudeCode.id,
            executableURL: executableURL,
            version: version
        )
    }
}
