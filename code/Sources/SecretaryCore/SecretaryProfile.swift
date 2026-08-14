import FunctionalCore
import Foundation

/// Who the assistant is: the name shown in the conversation, and the character
/// the model is asked to write as.
///
/// The user can have several of these and switch between them, so it carries an
/// `id` and is `Codable` — the pictures live on disk beside it, keyed by the
/// same id (see `ProfileStore`).
public struct SecretaryProfile: Identifiable, Equatable, Sendable, Codable {

    /// Male and female are offered as buttons because they're the common case;
    /// anything else is free text rather than a short list nobody fits.
    public enum Gender: Equatable, Sendable, Codable {
        case female, male
        case other(String)

        /// What the user sees in the picker.
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

    /// Either a life stage or an exact age — the charter allows both, and an
    /// exact age still implies a stage, so one derives from the other.
    public enum Age: Equatable, Sendable, Codable {
        case child, teenager, adult
        case years(Int)

        public enum Band: Sendable {
            case child, teenager, adult

            /// Used when the gender doesn't supply a noun of its own.
            var noun: String {
                switch self {
                case .child: return "a child"
                case .teenager: return "a teenager"
                case .adult: return "an adult"
                }
            }
        }

        /// An exact age is bucketed rather than described on its own, so the
        /// prompt reads the same whichever way it was entered.
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

        /// Only present when the user gave a number; the prompt mentions it then.
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

    /// What an unset or unusable personality falls back to, as specified.
    public static let defaultPersonality = "professional"

    public let id: UUID
    public var name: String
    public var age: Age
    public var gender: Gender
    /// Free text — "professional", "ขี้เล่น ร่าเริง", anything. Blank means the
    /// default; it is never interpreted here, only passed to the model as the
    /// character to write as, which the prompt then bounds.
    ///
    /// Called `style` until 0.6.126, when it was widened from a register hint to
    /// an actual character and the name stopped matching the job. Old profile
    /// files still say `style`; see `init(from:)`.
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

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, age, gender, personality
        /// What the field was called on disk before the rename.
        case style
    }

    /// Reads either spelling, so renaming the property does not throw away every
    /// profile the user has.
    ///
    /// This matters more than it looks: `ProfileStore.load()` returns an empty
    /// selection on any decode failure, and `ProfileLibrary` treats empty as a
    /// first launch and seeds Miku. A missing key would therefore not surface as
    /// an error — it would silently replace the user's profiles with the
    /// built-in one. New files are written with `personality`; old ones keep
    /// working until they are next saved.
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

    /// The character shipped with the app, matching the placeholder artwork.
    /// A fixed id so the built-in profile stays the same object across launches
    /// rather than multiplying every time the app starts.
    public static let miku = SecretaryProfile(
        id: UUID(uuidString: "5B1E2A00-0000-4000-8000-000000000001")!,
        name: "Miku",
        age: .years(17),
        gender: .female,
        personality: SecretaryProfile.defaultPersonality
    )

    /// The personality actually used: whitespace-only text is treated as unset.
    public var effectivePersonality: String {
        let trimmed = personality.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultPersonality : trimmed
    }

    /// Name with the blank case handled, so an empty field never renders an
    /// anonymous speaker label in the transcript.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Secretary" : trimmed
    }

    /// "a teenage girl", "a man", "a teenager, nonbinary" — the phrase that
    /// follows the name in the prompt.
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

    /// How who she is has to show up in languages that inflect for it.
    ///
    /// The descriptor above says "a teenage girl" — in English, where nothing
    /// downstream of that changes. Thai marks the speaker's gender in every
    /// polite sentence, and the model was left to infer the connection: Miku,
    /// set female, closed her replies with **ครับ** for weeks while อาเนีย, also
    /// female, said **ค่ะ**. Nothing was choosing; ครับ is simply where a model
    /// lands when no one says otherwise.
    ///
    /// So the consequence is spelled out rather than implied. Age is in here
    /// too, because Thai first-person pronouns are not only gendered — a small
    /// child says หนู, and a six-year-old saying ดิฉัน reads as a costume.
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

    /// Character notes for the system prompt.
    ///
    /// The personality is the user's own words and is granted as *character*,
    /// not as a register dial. It used to be clamped — "take that as register
    /// only — how formal or casual to sound", followed by "keep all of this in
    /// the tone, not in extra words" — and the result was that every profile
    /// sounded identical: "ขี้เล่น ร่าเริง ซึนเดเระ" and "professional" both
    /// produced the same flat two-line answer, which is what the owner
    /// reported. A description nobody can hear is the same as no description,
    /// so the grant is now wide enough to be audible in a one-sentence reply.
    ///
    /// Two things still bound it, and both are fixed text that outranks
    /// whatever the user typed:
    ///
    /// - Usefulness. Character changes *how* something is said, never whether
    ///   it is true or how much work gets done. Lead with the answer stays.
    /// - The romantic/sexual prohibition. It lives here rather than in a filter
    ///   over the text box because a keyword blocklist over free Thai and
    ///   English would both miss the real cases and reject innocent ones,
    ///   whereas the prompt is where the personality takes effect at all.
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
