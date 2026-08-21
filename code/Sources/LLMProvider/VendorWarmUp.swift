import FunctionalCore
import Foundation

/// One combination worth paying the first turn's cost for, ahead of time.
///
/// Measured on this Mac against opencode 1.18.15 + a local 27B on 2026-08-21,
/// because the numbers decide the whole design:
///
/// | | |
/// |---|---|
/// | opencode binary startup | 0.3s |
/// | loading the model (26.9 GB) | ~27s |
/// | prefilling opencode's 13,127-token prompt, cold | ~116s (~126 tok/s) |
/// | the same prefill once the cache holds it | 0.3s |
///
/// So keeping a *process* warm — the obvious idea — buys 0.3 seconds of a
/// two-minute wait and is not worth building. What costs the time is the model
/// re-reading the same 13k-token system prompt, and that is cached: pay it once
/// and later turns are seconds. This makes the app pay it when nobody is
/// waiting, instead of on the person's first question.
///
/// The three fields are exactly what changes the cached prefix. The directory is
/// in there because opencode reads the project's own rules files into the
/// prompt, so warming in one folder does nothing for another.
public struct WarmUpTarget: Hashable, Sendable {
    public let vendorID: String
    public let modelID: String?
    public let directory: String?

    public init(vendorID: String, modelID: String?, directory: String?) {
        self.vendorID = vendorID
        self.modelID = modelID
        self.directory = directory
    }
}

/// Whether to spend a couple of minutes of somebody's machine right now.
///
/// Deliberately narrow. This runs a real turn against a real model, which on a
/// laptop means fans and battery, so every reason to skip is checked here rather
/// than left to the caller to remember:
///
/// - the maker has to have something to warm at all (Claude Code does not — its
///   prompt is cached on Anthropic's side and its process is already kept warm);
/// - the same combination must not have been warmed already this run;
/// - and it must not be started while a turn is in flight, or the warm-up and
///   the person's own question queue behind each other on the same model and
///   both come back slower than if neither had run.
public func shouldWarmUp(
    _ target: WarmUpTarget,
    alreadyWarmed: Set<WarmUpTarget>,
    vendorWarmsUp: Bool,
    turnInFlight: Bool
) -> Bool {
    guard vendorWarmsUp, !turnInFlight else { return false }
    return !alreadyWarmed.contains(target)
}

public extension VendorRuntime {
    /// Sends one throwaway question so the model reads the maker's system prompt
    /// once, into its cache, before the person asks anything.
    ///
    /// **The flags have to match a real turn or this warms the wrong thing.**
    /// The cached prefix is built from the model, the working directory and the
    /// agent, so a warm-up that leaves out `--dir` prefills a prompt no later
    /// turn will ever send, and the person still waits the full two minutes.
    ///
    /// Deliberately *not* `--session`: this starts its own thread so a
    /// throwaway "hi" never appears in the conversation the person is having.
    /// The reply is dropped on the floor — the point is the prefill, not the
    /// answer.
    static func openCodeWarmUp(
        _ installation: AgentInstallation,
        directory: URL?,
        model: ChatModel?
    ) async {
        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = openCodeArguments(
            model: Option.fromOptional(model),
            variant: .none(),
            session: .none(),
            workingDirectory: directory,
            prompt: warmUpPrompt
        )
        process.environment = openCodeEnvironment(for: installation)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        // Blocks this task, not the app: the caller runs it detached. Waiting is
        // what makes "already warmed" true only once it really is.
        process.waitUntilExit()
    }

    /// Short, and asking for a short answer, because every token it generates is
    /// time added to a wait that exists to remove waiting.
    static let warmUpPrompt = "Reply with the single word: ready"
}
