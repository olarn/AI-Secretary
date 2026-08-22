import Foundation
import FunctionalCore
import Observation
import LLMProvider
import SecretaryCore

@MainActor
@Observable
final class VendorStatus {
    private let store: VendorChoiceStoring
    private let backend: ChatBackend
    private let claudeAvailability: () -> ClaudeCodeAvailability?
    private let chosenModel: () -> ChatModel?
    private let chooseModel: (ChatModel?) -> Void
    private let turnInFlight: () -> Bool
    private let workingDirectory: () -> URL?
    private var warmed: Set<WarmUpTarget> = []

    private(set) var choice: VendorChoice
    private(set) var connection: VendorConnection = .unchecked
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

    var cliPath: String { choice.cliPath.getOrElse("") }

    func choose(vendorID: String) {
        guard vendorID != choice.vendorID else { return }
        apply(choice.choosing(vendorID: vendorID))
    }

    func choose(cliPath: String) {
        let trimmed = cliPath.trimmingCharacters(in: .whitespaces)
        apply(choice.choosing(cliPath: trimmed.isEmpty ? .none() : .some(trimmed)))
    }

    private func apply(_ updated: VendorChoice) {
        choice = updated
        store.save(updated)
        models = runtime.vendor.models
        let kept = modelSurviving(Option.fromOptional(chosenModel()), switchingTo: runtime.vendor)
        chooseModel(kept.toOptional())
        refresh()
    }

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
        warmed.insert(target)
        Task.detached(priority: .utility) {
            await runtime.warmUp(installation, directory: directory, model: model)
        }
    }

    private static func locate(
        runtime: VendorRuntime,
        userPath: String?,
        claude: ClaudeCodeAvailability?
    ) async -> VendorExecutable {
        guard runtime.vendor.executableIsUserSupplied else {
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
