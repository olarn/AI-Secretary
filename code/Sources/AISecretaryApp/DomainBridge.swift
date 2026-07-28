import FunctionalCore
import Credentials
import Foundation
import ProjectRegistry
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

extension CredentialStore {
    /// The stored key as a plain optional, for callers that still take one.
    var apiKeyText: String? { apiKey().toOptional() }

    /// Saves the key. Returns the note to show, or `nil` on success.
    func saveAPIKeyReportingProblem(text: String) -> String? {
        setAPIKey(text: text).fold({ "Could not save: \($0.localizedDescription)" }, { nil })
    }

    func clearAPIKeyReportingProblem() -> String? {
        setAPIKey(.none()).fold({ "Could not clear: \($0.localizedDescription)" }, { nil })
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
