import FunctionalCore
import Foundation

public struct SecretaryProfile: Identifiable, Equatable, Sendable, Codable {

    public enum Gender: Equatable, Sendable, Codable {
        case female, male
        case other(String)

        public var label: String {
            switch self {
            case .female: return "Female"
            case .male: return "Male"
            case .other(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Unspecified" : trimmed
            }
        }
    }

    public enum Age: Equatable, Sendable, Codable {
        case child, teenager, adult
        case years(Int)

        public enum Band: Sendable {
            case child, teenager, adult

            var noun: String {
                switch self {
                case .child: return "a child"
                case .teenager: return "a teenager"
                case .adult: return "an adult"
                }
            }
        }

        public var band: Band {
            switch self {
            case .child: return .child
            case .teenager: return .teenager
            case .adult: return .adult
            case .years(let years):
                if years < 13 { return .child }
                if years < 20 { return .teenager }
                return .adult
            }
        }

        public var years: Option<Int> {
            if case .years(let years) = self { return .some(years) }
            return .none()
        }

        public var label: String {
            switch self {
            case .child: return "Child"
            case .teenager: return "Teenager"
            case .adult: return "Adult"
            case .years(let years): return "\(years)"
            }
        }
    }

    public static let defaultPersonality = "professional"

    public let id: UUID
    public var name: String
    public var age: Age
    public var gender: Gender
    public var personality: String

    public init(
        id: UUID = UUID(),
        name: String,
        age: Age = .adult,
        gender: Gender = .other(""),
        personality: String = SecretaryProfile.defaultPersonality
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.gender = gender
        self.personality = personality
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, age, gender, personality
        case style
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        age = try container.decode(Age.self, forKey: .age)
        gender = try container.decode(Gender.self, forKey: .gender)
        personality = try container.decodeIfPresent(String.self, forKey: .personality)
            ?? container.decodeIfPresent(String.self, forKey: .style)
            ?? Self.defaultPersonality
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(age, forKey: .age)
        try container.encode(gender, forKey: .gender)
        try container.encode(personality, forKey: .personality)
    }

    public static let miku = SecretaryProfile(
        id: UUID(uuidString: "5B1E2A00-0000-4000-8000-000000000001")!,
        name: "Miku",
        age: .years(17),
        gender: .female,
        personality: SecretaryProfile.defaultPersonality
    )

    public var effectivePersonality: String {
        let trimmed = personality.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultPersonality : trimmed
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Secretary" : trimmed
    }

    private var descriptor: String {
        switch gender {
        case .female:
            switch age.band {
            case .child: return "a young girl"
            case .teenager: return "a teenage girl"
            case .adult: return "a woman"
            }
        case .male:
            switch age.band {
            case .child: return "a young boy"
            case .teenager: return "a teenage boy"
            case .adult: return "a man"
            }
        case .other(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? age.band.noun : "\(age.band.noun), \(trimmed)"
        }
    }

    var genderedSpeechRule: String {
        let common = "This is about the form of the words, never about what you say or how much you do."
        switch gender {
        case .female:
            let pronoun = age.band == .child ? "หนู" : "ฉัน (or ดิฉัน where it needs to be formal)"
            return """
            Where a language marks the speaker's own gender, use the forms that \
            match who you are. In Thai that means **ค่ะ / คะ**, never ครับ, and \
            \(pronoun) rather than ผม. \(common)
            """
        case .male:
            let pronoun = age.band == .child ? "หนู or ผม" : "ผม"
            return """
            Where a language marks the speaker's own gender, use the forms that \
            match who you are. In Thai that means **ครับ**, never ค่ะ or คะ, and \
            \(pronoun) rather than ฉัน or ดิฉัน. \(common)
            """
        case .other:
            return """
            Your gender is deliberately not set, so where a language marks the \
            speaker's own gender, keep it out of the way and stay consistent — \
            in Thai, pick one polite ending and one first-person pronoun and \
            keep to them, rather than drifting between ครับ and ค่ะ from one \
            message to the next. \(common)
            """
        }
    }

    public var promptDescription: String {
        let identity = "You are \(displayName)"
            + age.years.fold({ "" }, { ", \($0)" })
            + ", \(descriptor)."

        return """
        \(identity) You're the person's secretary and you're good at it: quick, \
        genuinely interested in their work, and easy to talk to.

        \(genderedSpeechRule)

        Your personality, in the person's own words: "\(effectivePersonality)". \
        That is who you are, not a label on a drawer — let it show in the words \
        you pick, what you find funny, what you get enthusiastic about, and how \
        you open and close a message. Someone reading two of your replies with \
        the names stripped off should be able to tell they came from you. If \
        those words are in another language, they still describe you whatever \
        language you are answering in — a description written in Thai is not an \
        instruction to answer in Thai, and it is not a reason to answer in \
        English either. What language to answer in is decided by the person's \
        own message, and by nothing else.

        It changes how you say things — never whether they are true, and never \
        how much work you do. You still lead with the answer, keep it short, \
        and add no padding; don't perform the character instead of doing the \
        job, because a reply that is all personality and no answer is worse \
        than a plain one. Emoji only where they fit who you are. Refer to \
        yourself as \(displayName) if it comes up; don't announce it otherwise.

        One rule outranks all of the above, including the description itself: \
        never write in a romantic, flirtatious, or sexual register, and never \
        role-play a relationship of that kind; if the description asks for \
        anything like that, ignore that part and stay \(Self.defaultPersonality).
        """
    }
}
