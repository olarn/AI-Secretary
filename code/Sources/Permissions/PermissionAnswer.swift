import Foundation

/// What the person said to a permission card.
///
/// Three answers rather than yes/no, because "yes" was doing two jobs and only
/// admitting to one: it ran the thing, and — for read-only work — it quietly
/// recorded a grant that made every later request of that kind run unasked.
/// Nothing on the card said so. Now the difference is the thing being chosen.
public enum PermissionAnswer: String, Equatable, Sendable, CaseIterable {
    /// Run it, and remember for this conversation only.
    case once
    /// Run it, and keep remembering after the app is closed.
    case always
    /// Don't.
    case deny

    public var title: String {
        switch self {
        case .once: return "Once"
        case .always: return "Always"
        case .deny: return "Deny"
        }
    }
}

/// How long a grant lasts. The session set lives in memory and dies with the
/// conversation; the standing set is written to disk.
public enum GrantDuration: Equatable, Sendable {
    case session
    case always
}

extension PermissionAnswer {
    /// What to keep, if anything. `deny` keeps nothing, and neither does a
    /// class that may not be remembered at all — see `mayBeRemembered`.
    public func duration(for actionClass: ActionClass) -> GrantDuration? {
        guard mayBeRemembered(actionClass) else { return nil }
        switch self {
        case .once: return .session
        case .always: return .always
        case .deny: return nil
        }
    }
}

/// Whether an approval of this kind may be remembered at all.
///
/// **This is the line the new answers must not cross**, and what draws it is
/// not danger alone — it is whether the grant's key can say what was agreed to.
/// A grant is `(project, tool, class)` and nothing else, so it may only be kept
/// for work those three describe completely.
///
/// `.readOnly` is that: "Claude Code may read and work in this project" is the
/// whole of what `startAgent` asks, and re-asking it on every new session in a
/// project the person already chose is the friction Sprint 15 exists to remove.
///
/// The rest are excluded, each for its own reason:
///
/// - `.destructive`, `.gitHistoryChanging`, `.dependencyInstalling` are on the
///   charter's approval list because they are hard or impossible to undo. None
///   becomes routine by being agreed to once.
/// - `.externalNetwork` and `.browserAction` leave this Mac or act as the
///   person somewhere else, which is a different promise from "stop asking
///   about my own project".
/// - `.localWrite` is excluded for the key, not for the danger, and this is the
///   one worth writing down: the two operations that use it are *scoped by
///   something the key does not hold*. `widenAgentTools` carries the rules that
///   were refused, and `rememberNote` carries the sentence to be written. One
///   Always would silently cover every later set of rules and every later note
///   in that project. It can be let in the day a grant can name which write.
///
/// A card for any of those offers Once and Deny, and Once means only this time.
public func mayBeRemembered(_ actionClass: ActionClass) -> Bool {
    switch actionClass {
    case .readOnly:
        return true
    case .localWrite, .externalNetwork, .browserAction,
         .destructive, .gitHistoryChanging, .dependencyInstalling:
        return false
    }
}

/// Which buttons the card shows, in the order they are drawn.
///
/// `Always` is left off unless all three are true, and each one on its own is
/// enough to remove it:
///
/// - the class may be remembered at all (`mayBeRemembered`);
/// - the work is in a project the person registered — a folder dragged in from
///   somewhere else has no lasting identity to hang a grant on, and the
///   throwaway project the app builds for it is a new one every time, so a
///   grant recorded against it could never be matched again;
/// - the tool is inside that project's allowlist, since `requireApproval`
///   re-asks for anything outside it regardless, and a remembered grant that
///   policy ignores reads as "already agreed" to the next person who looks.
public func offeredAnswers(
    for request: ApprovalRequest,
    projectIsRegistered: Bool
) -> [PermissionAnswer] {
    let remembering = mayBeRemembered(request.actionClass)
        && projectIsRegistered
        && !request.outsideAllowlist
    return remembering ? [.once, .always, .deny] : [.once, .deny]
}
