import FunctionalCore
import Foundation

public struct CharacterCard: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let model: String
    public let effort: String
    public let projectName: Option<String>
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

public func characterDirectory(_ all: [CharacterCard], excluding me: UUID) -> [CharacterCard] {
    all.filter { $0.id != me }
        .sorted { ($0.name.lowercased(), $0.id.uuidString) < ($1.name.lowercased(), $1.id.uuidString) }
}

public func directoryPrompt(_ others: [CharacterCard]) -> Option<String> {
    guard !others.isEmpty else { return .none() }
    return .some("""
        Other characters live on this desktop with you. Each turn you are told \
        who they are and what each is doing, at the top of the message.

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

public func delegationCandidates(_ directory: [CharacterCard]) -> [CharacterCard] {
    directory.filter { !$0.isBusy }
}

public func directoryStatus(_ others: [CharacterCard]) -> Option<String> {
    guard !others.isEmpty else { return .none() }
    let rows = others.map { card in
        let place = card.projectName
            .map { "working in “\($0)”" }^
            .getOrElse("no project open")
        return "- \(card.name) — \(card.model), effort \(card.effort), \(place), \(card.isBusy ? "busy" : "free")"
    }
    return .some("""
        [The others, as this turn starts]
        \(rows.joined(separator: "\n"))
        Busy means mid-turn this moment; send anyway if you need them, the app \
        holds it until they are free.
        """)
}
