import FunctionalCore
import Foundation
import ProjectRegistry
import LLMProvider
import SecretaryCore

extension ProjectRegistry {
    func addReportingProblem(_ project: Project) -> String? {
        add(project).fold(
            { $0.reason },
            { added in added ? nil : "“\(project.name)” is already registered." }
        )
    }

    func removeReportingProblem(id: UUID) -> String? {
        remove(id: id).fold({ $0.reason }, { nil })
    }
}

@MainActor
extension ProfileLibrary {
    var artworkFileURL: URL? { artworkURL().toOptional() }

    func artworkFileURL(for id: UUID) -> URL? { artworkURL(for: id).toOptional() }

    func setArtworkReportingProblem(pngData: Data, for id: UUID) -> String? {
        setArtwork(pngData: pngData, for: id).fold({ $0.reason }, { _ in nil })
    }

    func clearArtworkReportingProblem(for id: UUID) -> String? {
        clearArtwork(for: id).fold({ $0.reason }, { nil })
    }
}

@MainActor
extension Secretary {
    var chosenModel: ChatModel? { model.toOptional() }
    var chosenEffort: Effort? { effort.toOptional() }

    func chooseModel(_ chosen: ChatModel?) { selectModel(Option.fromOptional(chosen)) }
    func chooseEffort(_ chosen: Effort?) { selectEffort(Option.fromOptional(chosen)) }

    var awaitingDecision: PendingDecision? { pendingDecision.toOptional() }
    var runningLoop: LoopSchedule? { activeLoop.toOptional() }
    var runningInstructions: InstructionRun? { activeInstructionRun.toOptional() }
    var workingSubagent: RunningSubagent? { runningSubagent.toOptional() }
    var fileRequestDescription: String? { fileRequest.toOptional() }
}

extension BackendStatus {
    var readiness: BackendReadiness {
        if needsOnboarding { return .notInstalled }
        guard let installation else { return .looking }
        return .ready(version: Option.fromOptional(installation.version))
    }
}
