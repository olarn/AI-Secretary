import Foundation
import Permissions

public struct ApprovalAsked: Equatable, Sendable {
    public let characterName: String
    public let question: String
    public let answers: [PermissionAnswer]

    public init(characterName: String, question: String, answers: [PermissionAnswer]) {
        self.characterName = characterName
        self.question = question
        self.answers = answers
    }
}
