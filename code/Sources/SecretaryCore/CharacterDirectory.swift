import FunctionalCore
import Foundation

/// One character as her neighbours are allowed to see her.
///
/// The type is the permission boundary, which is why it is worth having at all
/// rather than passing `SecretaryProfile` around. Sprint 14.2 asks that a
/// character know *which project* another has open and still have no access to
/// it — so this card carries the project's **name** and no path, no grant, no
/// tool id and no session id. A value cannot leak what it does not hold, and a
/// later field added here has to be argued for against that sentence.
public struct CharacterCard: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    /// As the app words it elsewhere — "Opus 5", "Default" — not a model id.
    public let model: String
    public let effort: String
    /// The name of the project she has open, if any. Never its location.
    public let projectName: Option<String>
    /// Whether she was mid-turn when this snapshot was taken.
    ///
    /// True only *as of that moment*. It is rendered into a prompt that a model
    /// may still be reading a minute later, so `directoryPrompt` says when it
    /// was true rather than stating it as a standing fact — a model told she is
    /// free, acting on it after she has started something, is a wrong-answer
    /// generator.
    public let isBusy: Bool

    public init(
        id: UUID,
        name: String,
        model: String,
        effort: String,
        projectName: Option<String> = .none(),
        isBusy: Bool = false
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.effort = effort
        self.projectName = projectName
        self.isBusy = isBusy
    }
}

/// Everyone except the character being prompted, in a stable order.
///
/// Sorted by name rather than left in roster order so the prompt text for an
/// unchanged desktop is byte-identical from turn to turn: a system prompt that
/// reshuffles itself is a prompt cache that never hits, and a test that has to
/// sort before comparing.
public func characterDirectory(_ all: [CharacterCard], excluding me: UUID) -> [CharacterCard] {
    all.filter { $0.id != me }
        .sorted { ($0.name.lowercased(), $0.id.uuidString) < ($1.name.lowercased(), $1.id.uuidString) }
}

/// How the roster is put to the model, or nothing when she is alone.
///
/// `.none()` rather than an empty string: a character by herself should have no
/// paragraph about her colleagues at all, and "there is nobody else" is a
/// sentence that invites the model to bring the subject up.
///
/// This paragraph alone answers Sprint 14.1's first item — knowing the others
/// exist and which model each is running needs no message sent and no round
/// trip, because the answer is already in front of her.
public func directoryPrompt(_ others: [CharacterCard]) -> Option<String> {
    guard !others.isEmpty else { return .none() }
    let rows = others.map { card in
        let place = card.projectName
            .map { "working in “\($0)”" }^
            .getOrElse("no project open")
        return "- \(card.name) — \(card.model), effort \(card.effort), \(place), \(card.isBusy ? "busy" : "free")"
    }
    return .some("""
        Other characters live on this desktop with you. As of the moment this \
        turn started:

        \(rows.joined(separator: "\n"))

        Whether one was busy was true when this turn started and may not be \
        true now, so don't promise the person that someone is free.

        You can see their names, their model and effort, and the name of the \
        project each has open. That is all you can see: you cannot read their \
        files, their projects or their conversations, and there is no path you \
        could ask for.

        **To send one of them something, end your message with a block like \
        this, and nothing after it:**

        ```to
        \(others.map(\.name).joined(separator: ", "))
        what you want done, in full, as you would say it to her
        ```

        The app delivers it, puts a line in both conversations, and brings you \
        the answers when they come. That block is the only way it happens.

        **Name everyone at once when the person asked for several.** They are \
        asked in parallel and you get every answer together — asking one, \
        waiting, then asking the next is slower and is not what was wanted. \
        Never say you will ask them one at a time.

        **None of your own tools can reach these characters.** They are not \
        Claude Code sessions, agents, or processes you can list or message, and \
        anything that looks like it would message them reaches something else \
        entirely. Never tell the person you have contacted, messaged, sent to \
        or heard from another character unless you used the block above in this \
        conversation and saw the app's own line confirming it — a report of \
        something that did not happen is worse than saying you couldn't.
        """)
}

/// Who the interruption card may offer the work to: everyone who is free.
///
/// An empty result *is* the requirement "nobody free, no delegate choice" — the
/// card draws one button per candidate, so an empty list means no buttons, and
/// there is no second branch that could disagree with this one.
///
/// The directory it reads is a snapshot taken as the card is drawn, so it can be
/// seconds stale by the time a button is pressed. That is exactly why pressing
/// one re-checks against live state (`delegationDeliverable`) instead of
/// trusting what the card was drawn from.
public func delegationCandidates(_ directory: [CharacterCard]) -> [CharacterCard] {
    directory.filter { !$0.isBusy }
}
