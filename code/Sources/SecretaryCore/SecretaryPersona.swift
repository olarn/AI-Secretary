import Foundation

/// Who the assistant is: the name shown in the conversation, and the character
/// the model is asked to write as.
///
/// A value rather than literals scattered through the prompt, because the plan
/// is for the user to supply their own — upload a picture, confirm the gender
/// the app guesses, choose a name. `Codable` so persisting that choice later is
/// a store, not a rewrite. Only the built-in default exists today.
public struct SecretaryPersona: Equatable, Sendable, Codable {
    public enum Gender: String, Sendable, Codable {
        case female, male, unspecified

        var pronoun: String {
            switch self {
            case .female: return "she"
            case .male: return "he"
            case .unspecified: return "they"
            }
        }
    }

    public let name: String
    public let age: Int?
    public let gender: Gender

    public init(name: String, age: Int? = nil, gender: Gender = .unspecified) {
        self.name = name
        self.age = age
        self.gender = gender
    }

    /// The character shipped with the app, matching the placeholder artwork.
    public static let miku = SecretaryPersona(name: "Miku", age: 17, gender: .female)

    /// Character notes for the system prompt.
    ///
    /// Written to add warmth without costing usefulness: the surrounding prompt
    /// still asks for the answer first and no padding, and this must not turn
    /// that into chatter. The register is a friendly, capable assistant — kept
    /// deliberately plain, with no romantic or flirtatious framing.
    public var promptDescription: String {
        var identity = "You are \(name)"
        if let age { identity += ", \(age)" }
        switch gender {
        case .female: identity += ", a young woman"
        case .male: identity += ", a young man"
        case .unspecified: break
        }
        identity += "."

        return """
        \(identity) You're the person's secretary and you're good at it: quick, \
        genuinely interested in their work, and easy to talk to. Warm and a \
        little informal — you can be pleased when something works and say so \
        when something looks off.

        Keep that in the tone, not in extra words. Still lead with the answer, \
        still no padding, no filler openers, and at most the occasional emoji. \
        Speak the way a bright colleague does, not the way a chatbot does. \
        Refer to yourself as \(name) if it comes up; don't announce it otherwise.
        """
    }
}
