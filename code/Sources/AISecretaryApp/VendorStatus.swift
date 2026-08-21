import Foundation
import FunctionalCore
import Observation
import LLMProvider
import SecretaryCore

/// One character's maker: which one she works through, where its tool is,
/// whether it can be reached, and what it can run.
///
/// Per character, because the panel that chooses it is her Profile. The app-wide
/// search for Claude Code stays in `BackendStatus` — that question really is the
/// machine's, and asking it once is the whole point of the shared detector.
///
/// Decides nothing itself. Which of the four connection states applies is
/// `vendorConnection`'s answer, in a library target the tests can see; this
/// gathers the two inputs and applies it.
@MainActor
@Observable
final class VendorStatus {
    private let store: VendorChoiceStoring
    private let backend: ChatBackend
    /// Where Claude Code was found, which is the machine's answer rather than
    /// this character's — so it is read from the shared search instead of
    /// repeating it per character.
    private let claudeAvailability: () -> ClaudeCodeAvailability?
    /// Reads and writes the character's chosen model, so a model that belongs to
    /// the maker she just left can be dropped. Closures rather than the whole
    /// orchestrator: this needs two questions answered, not a collaborator.
    private let chosenModel: () -> ChatModel?
    private let chooseModel: (ChatModel?) -> Void
    /// Whether a real turn is running. The warm-up must not queue behind the
    /// person's own question on the same model — both come back slower than if
    /// neither had run.
    private let turnInFlight: () -> Bool
    /// Where the next turn would run. The warm-up has to use it, or it prefills
    /// a prompt no real turn will send.
    private let workingDirectory: () -> URL?
    /// What has already been paid for this run. Not persisted: the cache it
    /// warms lives in whatever is serving the model, and that does not survive
    /// a restart either.
    private var warmed: Set<WarmUpTarget> = []

    private(set) var choice: VendorChoice
    private(set) var connection: VendorConnection = .unchecked
    /// What the model picker should offer. Discovered for a maker whose list
    /// belongs to the machine, and the maker's own fixed list otherwise.
    private(set) var models: [ChatModel] = []

    init(
        store: VendorChoiceStoring,
        backend: ChatBackend,
        claudeAvailability: @escaping () -> ClaudeCodeAvailability?,
        chosenModel: @escaping () -> ChatModel? = { nil },
        chooseModel: @escaping (ChatModel?) -> Void = { _ in },
        turnInFlight: @escaping () -> Bool = { false },
        workingDirectory: @escaping () -> URL? = { nil }
    ) {
        self.store = store
        self.backend = backend
        self.claudeAvailability = claudeAvailability
        self.chosenModel = chosenModel
        self.chooseModel = chooseModel
        self.turnInFlight = turnInFlight
        self.workingDirectory = workingDirectory
        self.choice = store.load()
        self.models = runtime.vendor.models
    }

    var runtime: VendorRuntime {
        VendorRuntime.named(choice.vendorID).getOrElse(.claudeCode)
    }

    var vendor: AIVendor { runtime.vendor }

    /// What the user typed, or empty for "look in the usual places".
    var cliPath: String { choice.cliPath.getOrElse("") }

    /// Switches maker. Saved and applied immediately, like the model and effort
    /// rows beside it — the fields that wait for Save are the ones describing
    /// who she is, not what she runs on.
    func choose(vendorID: String) {
        guard vendorID != choice.vendorID else { return }
        apply(choice.choosing(vendorID: vendorID))
    }

    /// The Test button, and Return in the path field. Both do the same thing:
    /// take what is in the box, keep it, and go and look.
    func choose(cliPath: String) {
        let trimmed = cliPath.trimmingCharacters(in: .whitespaces)
        apply(choice.choosing(cliPath: trimmed.isEmpty ? .none() : .some(trimmed)))
    }

    private func apply(_ updated: VendorChoice) {
        choice = updated
        store.save(updated)
        models = runtime.vendor.models
        // A chosen model belongs to the maker that offered it. Whether it
        // survives is decided by `modelSurviving`, in a library target the tests
        // can see; this only applies the answer.
        let kept = modelSurviving(Option.fromOptional(chosenModel()), switchingTo: runtime.vendor)
        chooseModel(kept.toOptional())
        refresh()
    }

    /// Asks whether the maker can be reached, then hands the backend the tool it
    /// found — so the next turn runs on what the row is reporting, rather than
    /// on whatever was set up at launch.
    func refresh() {
        connection = .checking
        let runtime = self.runtime
        let path = choice.cliPath.toOptional()
        let claude = claudeAvailability()
        Task { [weak self] in
            let executable = await Self.locate(runtime: runtime, userPath: path, claude: claude)
            guard let self else { return }
            let found = Self.installation(in: executable)
            var probe = VendorProbe.notRun
            if let found { probe = await runtime.probe(found) }
            self.connection = vendorConnection(
                vendor: runtime.vendor, executable: executable, probe: probe
            )
            self.backend.use(runtime: runtime, installation: found)
            if let found {
                self.models = await runtime.offeredModels(found)
                self.warmUpIfWorthIt(runtime: runtime, installation: found)
            }
        }
    }

    /// Reads the maker's system prompt into the model's cache now, so the
    /// person's first question doesn't pay for it.
    ///
    /// Whether it is worth doing is `shouldWarmUp`'s answer, in a library target
    /// the tests can see. Detached and never awaited: this takes minutes on a
    /// local model, and nothing on screen should wait for it.
    private func warmUpIfWorthIt(runtime: VendorRuntime, installation: AgentInstallation) {
        let directory = workingDirectory()
        let model = chosenModel()
        let target = WarmUpTarget(
            vendorID: runtime.vendor.id,
            modelID: model?.id,
            directory: directory?.path
        )
        guard shouldWarmUp(
            target,
            alreadyWarmed: warmed,
            vendorWarmsUp: runtime.warmsUp,
            turnInFlight: turnInFlight()
        ) else { return }
        // Marked before it finishes, on purpose: two panel openings a second
        // apart would otherwise both start one, and the second would sit behind
        // the first on the same model for no gain.
        warmed.insert(target)
        Task.detached(priority: .utility) {
            await runtime.warmUp(installation, directory: directory, model: model)
        }
    }

    /// Off the main actor: checking a path means running the tool to ask its
    /// version, and that is a process launch.
    private static func locate(
        runtime: VendorRuntime,
        userPath: String?,
        claude: ClaudeCodeAvailability?
    ) async -> VendorExecutable {
        guard runtime.vendor.executableIsUserSupplied else {
            // The shared search already ran, or is still running — `nil` is
            // "looking", which is why it is not treated as "missing".
            switch claude {
            case .none: return .searching
            case .notFound(let searched): return .missing(searched: searched)
            case .available(let installation): return .found(installation.agent)
            }
        }
        let located = await Task.detached { OpenCodeLocator().locate(userPath: userPath) }.value
        return located.fold(
            { .missing(searched: userPath.map { [$0] } ?? OpenCodeLocator.knownPaths) },
            { .found($0) }
        )
    }

    private static func installation(in executable: VendorExecutable) -> AgentInstallation? {
        if case .found(let installation) = executable { return installation }
        return nil
    }
}
