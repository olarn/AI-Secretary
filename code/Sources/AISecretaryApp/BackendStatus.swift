import Foundation
import Observation
import LLMProvider

/// What the UI knows about where work will run.
///
/// Detection can involve launching a login shell, so it happens on a background
/// task after launch and this object is how the result reaches the views. `nil`
/// means "still looking" — the panel shows neither the onboarding card nor a
/// confirmed backend until we actually know.
@MainActor
@Observable
final class BackendStatus {
    var availability: ClaudeCodeAvailability?

    var isChecking: Bool { availability == nil }

    var installation: ClaudeCodeInstallation? { availability?.installation }

    /// True only once we've looked and found nothing.
    var needsOnboarding: Bool {
        if case .notFound = availability { return true }
        return false
    }
}
