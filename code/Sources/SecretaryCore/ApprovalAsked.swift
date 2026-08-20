import Foundation
import Permissions

/// A permission card, as somebody outside the character's own chat sees it.
///
/// The command window is why this exists. Claude Code has no mid-turn
/// approval, so the only honest loop is try-refused-ask-retry (see
/// `offerToWiden`) — and the asking happened in the character's chat panel and
/// nowhere else. Commanded from the command window, every character that
/// wanted to write a file said it had no permission and then waited on a card
/// the person was never shown: either they happened to open her chat and
/// answer, or the work sat there for ever. That is the owner's report opening
/// Sprint 21.2, both halves of it, and it is one bug.
///
/// Carries the words rather than the `ApprovalRequest`: what the person has to
/// weigh is what will happen, and the sentence she just said is already written
/// for a human. The answers come from `offeredApprovalAnswers`, so the buttons
/// outside the chat and the buttons inside it can never differ.
public struct ApprovalAsked: Equatable, Sendable {
    public let characterName: String
    /// What she said when she put the card up, verbatim.
    public let question: String
    public let answers: [PermissionAnswer]

    public init(characterName: String, question: String, answers: [PermissionAnswer]) {
        self.characterName = characterName
        self.question = question
        self.answers = answers
    }
}
