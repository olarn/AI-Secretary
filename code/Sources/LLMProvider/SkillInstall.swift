import FunctionalCore
import Foundation

/// Installs a skill, once a human has said yes.
///
/// Its own protocol rather than another method on `ChatProvider`: installing
/// software is not chatting, the orchestrator has to be able to call it with no
/// turn in flight, and a test needs to assert that nothing was installed
/// without substituting the whole backend.
public protocol SkillInstalling: AnyObject, Sendable {
    /// - Returns: what the installer printed, or why it failed. Never throws:
    ///   a failed install is an answer the person has to be given, not an
    ///   error that unwinds a turn they are in the middle of.
    func installSkill(named plugin: String) async -> Either<String, String>
}

/// Whether this is a name the installer may be handed.
///
/// The owner's decision (2026-08-13) is that skills come from the configured
/// marketplaces and nowhere else, and the marketplace is what makes that true:
/// `claude plugin install` resolves a bare name against the marketplaces the
/// person has already added, and fails on anything else. This function's job is
/// only to stop the *name* from being something other than a name.
///
/// It matters because the string arrives from a model, and a model can be
/// talked into things by the page it just read. Nothing here reaches a shell —
/// arguments are passed as an array — so the risk is not injection but a name
/// that is really a flag (`--scope`), a path (`../…`), or a git URL, any of
/// which would quietly turn "install from the marketplace" into something else.
public func validSkillPluginName(_ name: String) -> Bool {
    guard !name.isEmpty, name.count <= 128, !name.hasPrefix("-") else { return false }
    // `plugin@marketplace` is the documented way to name one when two
    // marketplaces carry the same plugin, so the `@` is allowed — once.
    let parts = name.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }) else { return false }

    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-@")
    return name.lowercased().unicodeScalars.allSatisfy(allowed.contains)
}

/// The command that installs it.
///
/// `--yes` because there is no terminal here to answer a prompt, and the
/// question it would have asked has already been asked on the card. `--scope
/// user` so an installed skill belongs to the person rather than to whichever
/// project happened to be open when they said yes.
public func skillInstallArguments(plugin: String) -> [String] {
    ["plugin", "install", plugin, "--yes", "--scope", "user"]
}
