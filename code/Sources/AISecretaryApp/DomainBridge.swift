import FunctionalCore
import Foundation
import ProjectRegistry
import LLMProvider
import SecretaryCore

// MARK: - The view edge
//
// SwiftUI views MUST NOT import FunctionalCore. Bow exports its own `State`
// type, which shadows SwiftUI's `@State` property wrapper and makes every
// `@State var` in the file fail with "'State' is ambiguous for type lookup".
//
// So the conversion happens here instead: this file speaks Bow on one side and
// plain Swift on the other, and it contains no views. Everything a view needs
// from a domain type arrives as `String?`, `Bool`, or a plain value.

extension ProjectRegistry {
    /// Registers a project. Returns the note to show the user, or `nil` when
    /// it was added cleanly — both "already registered" and a failed write are
    /// things the user should see, and neither should be a silent `try?`.
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
    /// The active profile's picture as a plain optional, for the character view.
    var artworkFileURL: URL? { artworkURL().toOptional() }

    /// Stores a chosen picture. Returns the note to show, or `nil` on success.
    func setArtworkReportingProblem(pngData: Data, for id: UUID) -> String? {
        setArtwork(pngData: pngData, for: id).fold({ $0.reason }, { _ in nil })
    }

    func clearArtworkReportingProblem(for id: UUID) -> String? {
        clearArtwork(for: id).fold({ $0.reason }, { nil })
    }
}

@MainActor
extension Secretary {
    /// The chosen model, or `nil` while inheriting the backend's own — the
    /// shape the settings menu's checkmarks compare against.
    var chosenModel: ChatModel? { model.toOptional() }
    var chosenEffort: Effort? { effort.toOptional() }

    /// `nil` means "go back to inheriting".
    func chooseModel(_ chosen: ChatModel?) { selectModel(Option.fromOptional(chosen)) }
    func chooseEffort(_ chosen: Effort?) { selectEffort(Option.fromOptional(chosen)) }

    /// The three pieces of "something is in flight" the panel draws: a question
    /// waiting on the user, a standing check-back, and an instruction file being
    /// worked through. Each is an `Option` on the Secretary and a plain optional
    /// here, for the same reason as the two above — the views that read them are
    /// full of `@State`, so they can never see Bow's `Option`.
    var awaitingDecision: PendingDecision? { pendingDecision.toOptional() }
    var runningLoop: LoopSchedule? { activeLoop.toOptional() }
    var runningInstructions: InstructionRun? { activeInstructionRun.toOptional() }
}
