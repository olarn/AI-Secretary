import Foundation
import SecretaryCore

@MainActor
final class CharacterBus {
    private let roster: () -> [CharacterInstance]

    init(roster: @escaping () -> [CharacterInstance]) {
        self.roster = roster
    }

    func directory(excluding me: UUID) -> [CharacterCard] {
        characterDirectory(roster().map(\.card), excluding: me)
    }

    func deliver(_ message: CharacterMessage) {
        guard let recipient = roster().first(where: { $0.profileID == message.to }) else { return }
        Task { @MainActor in recipient.secretary.receive(message) }
    }
}

extension CharacterInstance {
    var card: CharacterCard {
        CharacterCard(
            id: profileID,
            name: secretary.profile.displayName,
            model: shortModelName(secretary.effectiveModelName),
            effort: secretary.effectiveEffortName,
            projectName: secretary.openProjectName,
            isBusy: stateMachine.state.isBusy
        )
    }
}
