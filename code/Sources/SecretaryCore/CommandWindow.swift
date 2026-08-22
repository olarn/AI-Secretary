import CoreGraphics
import Foundation

public enum CommandDispatch: Equatable, Sendable {
    case needSelection
    case namedNotSelected([String])
    case send(to: [CharacterCard])
}

public func commandRecipients(
    for text: String,
    selected: [CharacterCard],
    roster: [CharacterCard]
) -> CommandDispatch {
    guard !selected.isEmpty else { return .needSelection }

    let haystack = text.lowercased()
    let named = roster.filter { card in
        namesFor(card).contains { haystack.contains($0) }
    }
    let namedAndSelected = named.filter { card in selected.contains { $0.id == card.id } }

    if !named.isEmpty && namedAndSelected.isEmpty {
        return .namedNotSelected(named.map(\.name))
    }
    return .send(to: namedAndSelected.isEmpty ? selected : namedAndSelected)
}

public let selectAtLeastOneCharacterMessage = "Tick at least one character"

public func namedNotSelectedMessage(_ names: [String]) -> String {
    "\(names.joined(separator: ", ")) not ticked — tick them, or reword the command"
}

public func commandMessage(
    for recipient: CharacterCard,
    among recipients: [CharacterCard],
    instructions: String
) -> String {
    guard recipients.count > 1 else { return instructions }
    let others = recipients.filter { $0.id != recipient.id }.map(\.name).joined(separator: ", ")
    return """
    [Command window] This instruction was sent to you (\(recipient.name)) and \(others) at the same time. \
    If it assigns work to specific characters by name or by role, do only the parts meant for you and ignore the rest. \
    If it defines roles, remember yours and act by it from now on. \
    If work is left unassigned, divide it among yourselves — take a fair share and hand the rest off to the others.

    \(instructions)
    """
}

public func mergedInstructions(files: [String], typed: String) -> String {
    let parts = (files + [typed])
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return parts.joined(separator: "\n\n")
}

public let commandWindowOriginKey = "commandWindow.origin"

public func commandWindowOriginString(_ origin: CGPoint) -> String {
    "\(origin.x),\(origin.y)"
}

public func commandWindowOrigin(
    saved: String?,
    size: CGSize,
    visibleFrame: CGRect
) -> CGPoint {
    let centre = CGPoint(
        x: visibleFrame.midX - size.width / 2,
        y: visibleFrame.midY - size.height / 2
    )
    let parsed = saved
        .map { $0.split(separator: ",").compactMap { Double($0) } }
        .flatMap { parts in parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil }
    let wanted = parsed ?? centre
    return CGPoint(
        x: min(max(wanted.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width)),
        y: min(max(wanted.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))
    )
}

public let commandWindowWidthKey = "commandWindow.width"
public let commandWindowExtraHeightKey = "commandWindow.extraHeight"

public let commandWindowDefaultWidth: Double = 620

public func commandWindowWidth(saved: Double?) -> Double {
    guard let saved, saved > 0 else { return commandWindowDefaultWidth }
    return min(max(saved, 380), 1000)
}

public enum CommandDropRole: Equatable, Sendable {
    case instruction
    case attachment
}

public func commandDropRole(forExtension ext: String) -> CommandDropRole {
    ["md", "markdown", "txt", "text"].contains(ext.lowercased()) ? .instruction : .attachment
}

public let commandFontSizeKey = "commandWindow.fontSize"

public let commandWindowDefaultFontSize: Double = 13

public func clampedCommandFontSize(_ size: Double) -> Double {
    min(max(size, 10), 28)
}

public func commandWindowMenuTitle(isVisible: Bool) -> String {
    isVisible ? "Hide Command" : "Show Command"
}

public struct CommandTranscriptEntry: Equatable, Sendable {
    public let name: String
    public let text: String
    public let succeeded: Bool

    public init(name: String, text: String, succeeded: Bool) {
        self.name = name
        self.text = text
        self.succeeded = succeeded
    }
}

public func commandResultsMarkdown(_ entries: [CommandTranscriptEntry]) -> String {
    let body = entries.map { entry -> String in
        let heading = entry.succeeded ? "## \(entry.name)" : "## \(entry.name) — couldn't finish"
        let said = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return said.isEmpty ? heading : "\(heading)\n\n\(said)"
    }
    return (["# Command results"] + body).joined(separator: "\n\n") + "\n"
}

public let commandResultsFileName = "command-results.md"
