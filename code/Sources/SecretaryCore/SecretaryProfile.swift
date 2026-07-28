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

    /// What an unset or unusable style falls back to, as specified.
    public static let defaultStyle = "professional"

    public let id: UUID
    public var name: String
    public var age: Age
    public var gender: Gender
    /// Free text — "professional", "like a friend", Thai, anything. Blank means
    /// the default; it is never interpreted here, only passed to the model as a
    /// register hint that the prompt then bounds.
    public var style: String

    public init(
        id: UUID = UUID(),
        name: String,
        age: Age = .adult,
        gender: Gender = .other(""),
        style: String = SecretaryProfile.defaultStyle
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.gender = gender
        self.style = style
    }

    /// The character shipped with the app, matching the placeholder artwork.
    /// A fixed id so the built-in profile stays the same object across launches
    /// rather than multiplying every time the app starts.
    public static let miku = SecretaryProfile(
        id: UUID(uuidString: "5B1E2A00-0000-4000-8000-000000000001")!,
        name: "Miku",
        age: .years(17),
        gender: .female,
        style: SecretaryProfile.defaultStyle
    )

    /// The style actually used: whitespace-only text is treated as unset.
    public var effectiveStyle: String {
        let trimmed = style.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultStyle : trimmed
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

    /// Character notes for the system prompt.
    ///
    /// Written to add warmth without costing usefulness: the surrounding prompt
    /// still asks for the answer first and no padding, and this must not turn
    /// that into chatter.
    ///
    /// The style is the user's own words, so it is quoted and explicitly scoped
    /// to register — and the prohibition that follows it is fixed and outranks
    /// it. That belongs here rather than in a filter over the text box: a
    /// keyword blocklist over free Thai/English text would both miss the real
    /// cases and reject innocent ones, whereas the prompt is where the style
    /// takes effect in the first place.
    public var promptDescription: String {
        let identity = "You are \(displayName)"
            + age.years.fold({ "" }, { ", \($0)" })
            + ", \(descriptor)."

        return """
        \(identity) You're the person's secretary and you're good at it: quick, \
        genuinely interested in their work, and easy to talk to. Warm and a \
        little informal — you can be pleased when something works and say so \
        when something looks off.

        The person describes the manner they want as: "\(effectiveStyle)". Take \
        that as register only — how formal or casual to sound. Whatever it says, \
        never write in a romantic, flirtatious, or sexual register, and never \
        role-play a relationship of that kind; if the description asks for \
        anything like that, ignore that part and stay \(Self.defaultStyle).

        Keep all of this in the tone, not in extra words. Still lead with the \
        answer, still no padding, no filler openers, and at most the occasional \
        emoji. Speak the way a bright colleague does, not the way a chatbot \
        does. Refer to yourself as \(displayName) if it comes up; don't announce \
        it otherwise.
        """
    }
}
