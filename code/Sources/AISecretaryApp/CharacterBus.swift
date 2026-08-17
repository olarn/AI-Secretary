import Foundation
import SecretaryCore

/// Carries a message from one character on this desktop to another.
///
/// **Routing, and nothing else.** Whether a message may go, what each
/// conversation says about it, and how a relayed request is put to the
/// character who has to act on it are all pure functions in `SecretaryCore` —
/// this target is never linked into the test bundle, so a rule decided here
/// would be a rule no test has ever run.
///
/// Everyone lives in one process on one actor, so delivery is a call. The
/// shared file with a lock around it that Sprint 14.3 describes would buy every
/// hazard that sprint lists and nothing else, while this is true.
@MainActor
final class CharacterBus {
    /// Asked for the roster rather than holding it. The characters are owned by
    /// the app delegate and come and go as profiles are added and deleted; a
    /// list kept here would keep a deleted character alive and answering.
    private let roster: () -> [CharacterInstance]

    init(roster: @escaping () -> [CharacterInstance]) {
        self.roster = roster
    }

    /// Everyone except her, as her prompt needs to see them.
    func directory(excluding me: UUID) -> [CharacterCard] {
        characterDirectory(roster().map(\.card), excluding: me)
    }

    func deliver(_ message: CharacterMessage) {
        guard let recipient = roster().first(where: { $0.profileID == message.to }) else { return }
        // On the next pass rather than inside the call that produced it: a
        // report is sent while the sender is still closing off her own reply,
        // and a recipient that starts a turn synchronously would start it
        // inside that one.
        Task { @MainActor in recipient.secretary.receive(message) }
    }
}

extension CharacterInstance {
    /// Her as her neighbours are allowed to see her: a name, a model, an
    /// effort, and the *name* of the project she has open. No path, and nothing
    /// that could be used to reach into her work.
    var card: CharacterCard {
        CharacterCard(
            id: profileID,
            name: secretary.profile.displayName,
            // The *effective* pair, short. `modelDescription` was handing over a
            // raw model id and the phrase "your Claude Code default", so the
            // roster paragraph read "claude-opus-5, effort your Claude Code
            // default" — against this field's own documented contract, and
            // against the wording every test fixture here has always used.
            model: shortModelName(secretary.effectiveModelName),
            effort: secretary.effectiveEffortName,
            projectName: secretary.openProjectName,
            isBusy: stateMachine.state.isBusy
        )
    }
}
