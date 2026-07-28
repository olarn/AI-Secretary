import FunctionalCore
import Foundation

/// Anything thrown inside a provider becomes a typed `ChatError` before it
/// reaches the stream. Without this the left rail would carry an untyped
/// `Error` and every consumer would be back to guessing.
///
/// `otherwise` is the caller's, not a default: a `URLError` from the HTTP
/// provider is a network failure, while the same untyped error from the Claude
/// Code provider means its process misbehaved. One shared fallback briefly told
/// API-key users "Claude Code failed: The Internet connection appears to be
/// offline" — on a path where Claude Code is not involved at all.
func asChatError(_ error: Error, otherwise fallback: (String) -> ChatError) -> ChatError {
    (error as? ChatError) ?? fallback(error.localizedDescription)
}
